/// 社区版图片预览状态，负责恢复本地图片和保存远程图片。
library;

import 'dart:async';

import 'package:get/get.dart';

import '../../core/session/session_controller.dart';
import '../../data/local/im_local_database.dart';
import '../../data/local/im_pending_attachment_store.dart';
import '../../data/models/message_model.dart';
import '../../data/services/file_transfer_service.dart';
import '../../data/services/image_cache_service.dart';
import '../../shared/utils/app_toast.dart';

class MediaPreviewItemContext {
  const MediaPreviewItemContext({
    this.senderName,
    this.senderAvatarUrl,
    this.createdAt,
  });

  final String? senderName;
  final String? senderAvatarUrl;
  final DateTime? createdAt;
}

class MediaPreviewArguments {
  const MediaPreviewArguments({
    required this.attachments,
    required this.initialIndex,
    this.itemContexts,
    this.clientMessageId,
  });

  final List<MessageAttachment> attachments;
  final int initialIndex;

  final List<MediaPreviewItemContext>? itemContexts;

  /// 待发送消息用它从 SQLite 的附件表恢复原文件；服务端消息可为空。
  final String? clientMessageId;
}

class MediaPreviewController extends GetxController {
  MediaPreviewController(
    this.arguments,
    this._transfers,
    this._database,
    this._attachmentStore,
    this._imageCache,
    this._session,
  );

  final MediaPreviewArguments arguments;
  final FileTransferService _transfers;
  final ImLocalDatabase _database;
  final ImPendingAttachmentStore _attachmentStore;
  final ImageCacheService _imageCache;
  final SessionController _session;

  final currentIndex = 0.obs;

  /// 仅汇总当前可见媒体的首轮读取；相邻图片预加载不占用顶栏。
  final _imageLoading = <int, bool>{}.obs;
  final _restoringImages = <int, int>{}.obs;

  bool get isCurrentMediaLoading {
    final index = currentIndex.value;
    return (_restoringImages[index] ?? 0) > 0 ||
        (_imageLoading[index] ?? false);
  }

  /// 图片组件把加载生命周期转交控制器；页面退出后的回调直接忽略。
  void reportImageLoading(int index, bool loading) {
    if (!isClosed && _imageLoading[index] != loading) {
      _imageLoading[index] = loading;
    }
  }

  final isSaving = false.obs;
  final saveProgress = 0.0.obs;
  final restoredImageBytes = <int, List<int>>{}.obs;
  final imageRestoreErrors = <int, String>{}.obs;

  List<MessageAttachment> get attachments => arguments.attachments;
  MediaPreviewItemContext contextAt(int index) {
    final contexts = arguments.itemContexts;
    if (contexts == null || contexts.length != attachments.length) {
      return const MediaPreviewItemContext();
    }
    return contexts[index];
  }

  MessageAttachment? get currentAttachment => attachments.isEmpty
      ? null
      : attachments[currentIndex.value.clamp(0, attachments.length - 1)];
  MediaPreviewItemContext get currentItemContext => attachments.isEmpty
      ? const MediaPreviewItemContext()
      : contextAt(currentIndex.value.clamp(0, attachments.length - 1));

  String get currentFilename {
    final item = currentAttachment;
    final name = item?.fileName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final resourceId = item?.resourceId.trim();
    if (resourceId != null && resourceId.isNotEmpty) return resourceId;
    return '图片';
  }

  @override
  void onInit() {
    super.onInit();
    if (attachments.isEmpty) return;
    currentIndex.value = arguments.initialIndex.clamp(
      0,
      attachments.length - 1,
    );
    unawaited(restoreImage(currentIndex.value));
  }

  Future<void> changePage(int index) async {
    if (index == currentIndex.value) return;
    currentIndex.value = index;
    await restoreImage(index);
  }

  List<int>? imageBytes(int index) =>
      attachments[index].localPreviewBytes ?? restoredImageBytes[index];

  /// Web 刷新后 Blob URL 已失效，必须重新读取 SQLite BLOB；原生端同样从
  /// 应用私有暂存文件读取，不能继续依赖系统选择器 URI。
  Future<void> restoreImage(int index) async {
    _restoringImages[index] = (_restoringImages[index] ?? 0) + 1;
    try {
      if (index < 0 || index >= attachments.length) return;
      final item = attachments[index];
      if (item.localPreviewBytes?.isNotEmpty == true ||
          restoredImageBytes.containsKey(index)) {
        return;
      }

      // 聊天气泡成功显示过的远程图片会进入统一媒体缓存。全屏预览必须先读
      // 同一份持久化缓存，断网时仍可查看，且不能再次请求远程地址。
      final cached = await _cachedImageBytes(index, item);
      if (cached != null && cached.isNotEmpty) {
        restoredImageBytes[index] = cached;
        imageRestoreErrors.remove(index);
        return;
      }

      // 有服务端地址但本地尚未缓存时，预览页继续按原逻辑加载网络图片。
      // 待发送图片没有服务端地址，才需要从 SQLite 附件暂存恢复。
      if (item.resourceUrl?.trim().isNotEmpty == true) return;
      final clientMessageId = arguments.clientMessageId?.trim();
      if (clientMessageId == null || clientMessageId.isEmpty) return;
      try {
        final records = await _database.readPendingAttachments(clientMessageId);
        for (final record in records) {
          if (record.attachmentIndex != index || record.role != 'original') {
            continue;
          }
          final bytes = await _attachmentStore.read(
            localPath: record.localPath,
            storedBytes: record.storedBytes,
          );
          restoredImageBytes[index] = bytes;
          imageRestoreErrors.remove(index);
          return;
        }
        imageRestoreErrors[index] = '本地图片已丢失';
      } catch (_) {
        imageRestoreErrors[index] = '本地图片读取失败';
      }
    } finally {
      if (!isClosed) {
        final remaining = (_restoringImages[index] ?? 1) - 1;
        if (remaining == 0) {
          _restoringImages.remove(index);
        } else {
          _restoringImages[index] = remaining;
        }
      }
    }
  }

  Future<List<int>?> _cachedImageBytes(
    int index,
    MessageAttachment attachment,
  ) async {
    final ownerId = _session.currentUser.value?.id.trim() ?? '';
    final resourceId = attachment.resourceId.trim();
    final url = attachment.resourceUrl?.trim() ?? '';
    if (ownerId.isEmpty || resourceId.isEmpty || url.isEmpty) return null;
    return _imageCache.cachedBytes(
      ImageCacheRequest(
        ownerId: ownerId,
        resourceId: resourceId,
        url: url,
            totalBytes: attachment.fileSize ?? 0,
        ),
    );
  }

  Future<void> saveCurrent() async {
    if (isSaving.value || attachments.isEmpty) return;
    final item = currentAttachment!;
    final url = item.resourceUrl?.trim();
    if (url == null || url.isEmpty) {
      AppToast.warning('图片仍在发送中，发送完成后可保存');
      return;
    }
    isSaving.value = true;
    saveProgress.value = 0;
    try {
      await _transfers.saveMedia(
        url: url,
        filename: currentFilename,
        isVideo: false,
        onProgress: (received, total) {
          if (total > 0) saveProgress.value = received / total;
        },
      );
      AppToast.success('保存成功');
    } catch (_) {
      AppToast.error('保存失败，请重试');
    } finally {
      isSaving.value = false;
      saveProgress.value = 0;
    }
  }

}

/// IM 本地优先发送服务。
///
/// 所有消息必须先原子写入 SQLite，再请求上传或消息接口。服务端通过
/// client_msg_id 保证幂等；HTTP、实时事件与增量同步最终归并同一条本地消息。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../domain/repositories/im_repository.dart';
import '../../domain/repositories/message_upload_repository.dart';
import '../enums/message_status.dart';
import '../local/im_local_database.dart';
import '../local/im_pending_attachment_store.dart';
import '../local/session_storage.dart';
import '../models/im_api_models.dart';
import '../models/message_model.dart';
import '../models/message_media_merge.dart';

class PendingMessageConfirmationException implements Exception {
  const PendingMessageConfirmationException(this.message);
  final String message;
}

class PendingAttachmentUploadPausedException implements Exception {
  const PendingAttachmentUploadPausedException();
}

enum AttachmentUploadPhase {
  preparing,
  waiting,
  uploading,
  paused,
  processing,
  completed,
}

/// 单条待发送消息中某个原附件的独立上传状态。缩略图不单独占用进度圈；原文件
/// 到达 100% 后进入 processing，待封面和消息附件确认完成后再标记 completed。
class AttachmentUploadProgressState {
  const AttachmentUploadProgressState({
    required this.clientMessageId,
    required this.attachmentIndex,
    required this.phase,
    required this.progress,
    required this.canPause,
  });

  final String clientMessageId;
  final int attachmentIndex;
  final AttachmentUploadPhase phase;
  final double progress;
  final bool canPause;

  String get key => '$clientMessageId:$attachmentIndex';

  AttachmentUploadProgressState copyWith({
    AttachmentUploadPhase? phase,
    double? progress,
    bool? canPause,
  }) => AttachmentUploadProgressState(
    clientMessageId: clientMessageId,
    attachmentIndex: attachmentIndex,
    phase: phase ?? this.phase,
    progress: progress ?? this.progress,
    canPause: canPause ?? this.canPause,
  );
}

/// 后台补发状态事件，用 client_msg_id 定位原本地气泡。
class PendingMessageStateChange {
  const PendingMessageStateChange({
    required this.clientMessageId,
    required this.conversationId,
    required this.status,
    this.message,
    this.errorMessage,
  });

  final String clientMessageId;
  final String conversationId;
  final MessageStatus status;
  final MessageModel? message;
  final String? errorMessage;
}

/// 将内部异常收敛为可以直接展示在消息气泡中的文案。
String pendingMessageErrorText(Object error, {String fallback = '发送失败，请重试'}) {
  if (error is ApiException && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }
  if (error is TimeoutException) return '连接超时，请检查网络后重试';
  return fallback;
}

/// 一条成组媒体消息中的本地附件及其发送元数据。
class PendingMediaAttachment {
  const PendingMediaAttachment({
    required this.file,
    this.thumbnail,
    this.width,
    this.height,
    this.durationMs,
    this.previewBytes,
    this.sourcePath,
    this.sourceSize,
  });

  final MessageUploadFile file;
  final MessageUploadFile? thumbnail;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<int>? previewBytes;
  final String? sourcePath;
  final int? sourceSize;

  int get originalSize => sourceSize ?? file.size;
}

class ImPendingMessageService {
  ImPendingMessageService(
    this._database,
    this._repository,
    this._uploadRepository,
    this._storage,
    this._attachmentStore,
  );

  final ImLocalDatabase _database;
  final ImRepository _repository;
  final MessageUploadRepository _uploadRepository;
  final SessionStorage _storage;
  final ImPendingAttachmentStore _attachmentStore;
  bool _retrying = false;
  final Set<String> _activeClientMessageIds = <String>{};
  final StreamController<PendingMessageStateChange> _stateController =
      StreamController<PendingMessageStateChange>.broadcast();
  final StreamController<AttachmentUploadProgressState>
  _uploadProgressController =
      StreamController<AttachmentUploadProgressState>.broadcast(sync: true);
  final Map<String, AttachmentUploadProgressState> _uploadStates = {};
  final Map<String, CancelToken> _activeUploadTokens = {};
  final Set<String> _pausedUploads = {};
  final Map<String, Map<String, dynamic>> _activeUploadItems = {};
  final Set<String> _resumeWatchers = {};

  Stream<PendingMessageStateChange> get stateChanges => _stateController.stream;
  Stream<AttachmentUploadProgressState> get uploadProgressChanges =>
      _uploadProgressController.stream;

  AttachmentUploadProgressState? uploadState(
    String clientMessageId,
    int attachmentIndex,
  ) => _uploadStates['$clientMessageId:$attachmentIndex'];

  Future<void> enqueueText({
    required MessageModel message,
    required String bodyText,
    String? replyMessageId,
  }) async {
    await _database.enqueuePendingMessage(
      message: message,
      payload: {
        'kind': 'text',
        'body_text': bodyText,
        if (replyMessageId != null && replyMessageId.isNotEmpty)
          'reply_message_id': replyMessageId,
      },
    );
    _publishEnqueued(message);
  }

  Future<void> enqueueRich({
    required MessageModel message,
    required String messageType,
    String? replyMessageId,
  }) async {
    await _database.enqueuePendingMessage(
      message: message,
      payload: {
        'kind': 'rich',
        'message_type': messageType,
        if (replyMessageId != null && replyMessageId.isNotEmpty)
          'reply_message_id': replyMessageId,
      },
    );
    _publishEnqueued(message);
  }

  /// 暂存附件后再原子入队。原生保存私有路径，Web 保存 SQLite BLOB。
  Future<void> enqueueAttachment({
    required MessageModel message,
    required MessageUploadFile file,
    required String messageType,
    String? sourcePath,
    int? sourceSize,
    int? width,
    int? height,
    int? durationMs,
    List<double> waveform = const [],
  }) async {
    final clientMessageId = message.clientMsgId ?? '';
    final user = await _storage.readUser();
    if (user == null || clientMessageId.isEmpty) {
      throw const ApiException(
        code: 'LOCAL_MESSAGE_INVALID',
        message: '本地消息身份无效，消息未发送',
      );
    }
    final staged = await _attachmentStore.stage(
      userId: user.id,
      storageKey: '$clientMessageId.0.original',
      bytes: file.bytes,
      sourcePath: sourcePath,
    );
    try {
      await _database.enqueuePendingMessage(
        message: message,
        payload: {
          'kind': 'attachment_upload',
          'message_type': messageType,
          'items': [
            {
              'index': 0,
              'upload_paused': false,
              if (width != null) 'width': width,
              if (height != null) 'height': height,
              if (durationMs != null) 'duration_ms': durationMs,
              if (waveform.isNotEmpty) 'waveform': waveform,
            },
          ],
          if (width != null) 'width': width,
          if (height != null) 'height': height,
          if (durationMs != null) 'duration_ms': durationMs,
          if (waveform.isNotEmpty) 'waveform': waveform,
        },
        attachment: staged,
        attachmentFilename: file.filename,
        attachmentMimeType: file.mimeType,
        attachmentSize: sourceSize ?? file.size,
      );
      _publishUploadState(
        AttachmentUploadProgressState(
          clientMessageId: clientMessageId,
          attachmentIndex: 0,
          phase: AttachmentUploadPhase.waiting,
          progress: 0,
          canPause: (sourceSize ?? file.size) > 20 * 1024 * 1024,
        ),
      );
      _publishEnqueued(message);
    } catch (_) {
      await _attachmentStore.delete(staged.localPath);
      rethrow;
    }
  }

  /// 将一组图片或视频作为同一条本地消息原子入队。
  Future<void> enqueueMediaGroup({
    required MessageModel message,
    required String messageType,
    required List<PendingMediaAttachment> attachments,
  }) async {
    final clientMessageId = message.clientMsgId ?? '';
    final user = await _storage.readUser();
    if (user == null || clientMessageId.isEmpty || attachments.isEmpty) {
      throw const ApiException(
        code: 'LOCAL_MESSAGE_INVALID',
        message: '本地多媒体消息无效，消息未发送',
      );
    }
    final writes = <PendingAttachmentWrite>[];
    try {
      for (var index = 0; index < attachments.length; index++) {
        final item = attachments[index];
        final original = await _attachmentStore.stage(
          userId: user.id,
          storageKey: '$clientMessageId.$index.original',
          bytes: item.file.bytes,
          sourcePath: item.sourcePath,
        );
        writes.add(
          PendingAttachmentWrite(
            attachmentIndex: index,
            role: 'original',
            filename: item.file.filename,
            mimeType: item.file.mimeType,
            fileSize: item.originalSize,
            staged: original,
          ),
        );
        final thumbnail = item.thumbnail;
        if (thumbnail != null) {
          final stagedThumbnail = await _attachmentStore.stage(
            userId: user.id,
            storageKey: '$clientMessageId.$index.thumbnail',
            bytes: thumbnail.bytes,
          );
          writes.add(
            PendingAttachmentWrite(
              attachmentIndex: index,
              role: 'thumbnail',
              filename: thumbnail.filename,
              mimeType: thumbnail.mimeType,
              fileSize: thumbnail.size,
              staged: stagedThumbnail,
            ),
          );
        }
      }
      await _database.enqueuePendingMessage(
        message: message,
        payload: {
          'kind': 'attachment_group_upload',
          'message_type': messageType,
          'items': [
            for (var index = 0; index < attachments.length; index++)
              {
                'index': index,
                'upload_paused': false,
                if (attachments[index].width != null)
                  'width': attachments[index].width,
                if (attachments[index].height != null)
                  'height': attachments[index].height,
                if (attachments[index].durationMs != null)
                  'duration_ms': attachments[index].durationMs,
              },
          ],
        },
        attachments: writes,
      );
      for (var index = 0; index < attachments.length; index++) {
        _publishUploadState(
          AttachmentUploadProgressState(
            clientMessageId: clientMessageId,
            attachmentIndex: index,
            phase: AttachmentUploadPhase.waiting,
            progress: 0,
            canPause: attachments[index].originalSize > 20 * 1024 * 1024,
          ),
        );
      }
      _publishEnqueued(message);
    } catch (_) {
      for (final write in writes) {
        await _attachmentStore.delete(write.staged.localPath);
      }
      rethrow;
    }
  }

  /// 重连或回前台后按入队顺序自动补发全部消息和附件。
  Future<void> retryPending() async {
    if (_retrying) return;
    _retrying = true;
    try {
      final records = await _database.readPendingMessages();
      for (final record in records) {
        if (_activeClientMessageIds.contains(record.clientMessageId)) break;
        try {
          await _database.updatePendingMessageStatus(
            record.clientMessageId,
            MessageStatus.sending,
          );
          _stateController.add(
            PendingMessageStateChange(
              clientMessageId: record.clientMessageId,
              conversationId: record.conversationId,
              status: MessageStatus.sending,
            ),
          );
          final message = await _attempt(record);
          _stateController.add(
            PendingMessageStateChange(
              clientMessageId: record.clientMessageId,
              conversationId: record.conversationId,
              status: MessageStatus.sent,
              message: message,
            ),
          );
        } on PendingAttachmentUploadPausedException {
          // 用户暂停不是发送失败，也不能阻断队列中其他待发送消息。
          continue;
        } on PendingMessageConfirmationException catch (error) {
          _stateController.add(
            PendingMessageStateChange(
              clientMessageId: record.clientMessageId,
              conversationId: record.conversationId,
              status: MessageStatus.failed,
              errorMessage: error.message,
            ),
          );
          // 服务端已经成功，本地等待实时事件或下一次同步修复，不能继续并发补发。
          break;
        } catch (error) {
          final errorText = pendingMessageErrorText(error);
          _stateController.add(
            PendingMessageStateChange(
              clientMessageId: record.clientMessageId,
              conversationId: record.conversationId,
              status: MessageStatus.failed,
              errorMessage: errorText,
            ),
          );
          break;
        }
      }
    } finally {
      _retrying = false;
    }
  }

  /// 发送或手动重试指定消息；不存在待发送记录时返回 null。
  Future<MessageModel?> sendPending(String clientMessageId) async {
    final record = await _database.readPendingMessage(clientMessageId);
    if (record == null) return null;
    await _database.updatePendingMessageStatus(
      clientMessageId,
      MessageStatus.sending,
    );
    return _attempt(record);
  }

  /// SQLite 的消息和会话投影均已提交后再发布，页面不会读到半完成状态。
  void _publishEnqueued(MessageModel message) {
    _stateController.add(
      PendingMessageStateChange(
        clientMessageId: message.clientMsgId ?? message.id,
        conversationId: message.conversationId ?? '',
        status: MessageStatus.sending,
        message: message,
      ),
    );
  }

  void _publishUploadState(AttachmentUploadProgressState state) {
    _uploadStates[state.key] = state;
    _uploadProgressController.add(state);
  }

  /// 点击附件进度圈时暂停或继续一个 Multipart 原文件。
  ///
  /// Single 文件没有暂停能力；暂停会取消当前分片 PUT，但已经由 S3 确认的
  /// ETag 保留。继续时重新 ListParts 对账，因此不会相信可能中断在响应途中的
  /// 本地进度。
  Future<void> toggleAttachmentUpload(
    String clientMessageId,
    int attachmentIndex,
  ) async {
    final key = '$clientMessageId:$attachmentIndex';
    final current = _uploadStates[key];
    if (current == null || !current.canPause) return;
    final shouldPause = current.phase != AttachmentUploadPhase.paused;
    final activeItem = _activeUploadItems[key];
    if (shouldPause) {
      _pausedUploads.add(key);
      if (activeItem != null) activeItem['upload_paused'] = true;
      _activeUploadTokens[key]?.cancel('user_paused');
      _publishUploadState(
        current.copyWith(phase: AttachmentUploadPhase.paused),
      );
    } else {
      _pausedUploads.remove(key);
      if (activeItem != null) activeItem['upload_paused'] = false;
      _publishUploadState(
        current.copyWith(phase: AttachmentUploadPhase.waiting),
      );
    }
    try {
      await _database.setPendingAttachmentUploadPaused(
        clientMessageId,
        attachmentIndex,
        shouldPause,
      );
    } catch (_) {
      // SQLite 未确认时回滚可见状态，避免界面显示“已暂停”但重启后自动上传。
      if (shouldPause) {
        _pausedUploads.remove(key);
        if (activeItem != null) activeItem['upload_paused'] = false;
      } else {
        _pausedUploads.add(key);
        if (activeItem != null) activeItem['upload_paused'] = true;
      }
      _publishUploadState(current);
      rethrow;
    }
    if (shouldPause) return;
    // 当前消息仍在处理其他附件时，上传调度循环会自动发现已恢复项；否则由
    // 这里重新启动同一 client_msg_id 的幂等发送流程。
    unawaited(_resumePendingWhenIdle(clientMessageId));
  }

  Future<void> _resumePendingWhenIdle(String clientMessageId) async {
    if (!_resumeWatchers.add(clientMessageId)) return;
    try {
      while (_activeClientMessageIds.contains(clientMessageId)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // 若原调度循环已经吸收“继续”操作并完成消息，记录此时已经不存在。
      if (await _database.readPendingMessage(clientMessageId) == null) return;
      await _resumePendingAfterUserAction(clientMessageId);
    } finally {
      _resumeWatchers.remove(clientMessageId);
    }
  }

  Future<void> _resumePendingAfterUserAction(String clientMessageId) async {
    final record = await _database.readPendingMessage(clientMessageId);
    if (record == null) return;
    try {
      final message = await _attempt(record);
      _stateController.add(
        PendingMessageStateChange(
          clientMessageId: clientMessageId,
          conversationId: record.conversationId,
          status: MessageStatus.sent,
          message: message,
        ),
      );
    } on PendingAttachmentUploadPausedException {
      // 仍有其他附件保持暂停，消息继续保留为待发送。
    } catch (error) {
      _stateController.add(
        PendingMessageStateChange(
          clientMessageId: clientMessageId,
          conversationId: record.conversationId,
          status: MessageStatus.failed,
          errorMessage: pendingMessageErrorText(error),
        ),
      );
    }
  }

  Future<MessageModel> _attempt(PendingMessageRecord record) async {
    final clientMessageId = record.clientMessageId;
    if (!_activeClientMessageIds.add(clientMessageId)) {
      throw const ApiException(
        code: 'MESSAGE_SEND_IN_PROGRESS',
        message: '消息正在发送，请勿重复操作',
      );
    }
    try {
      // 多附件消息可能包含 9 个原文件和 9 个封面，不能用一个总超时包住
      // 整组流程；Dio 会分别约束每次上传和最终消息请求。
      var result = await _dispatch(record);
      try {
        final local = await _database.readPendingLocalMessage(clientMessageId);
        final confirmed = local == null
            ? result.copyWith(clientMsgId: clientMessageId)
            : local.copyWith(
                id: result.id,
                clientMsgId: clientMessageId,
                seq: result.seq,
                time: result.time,
                senderId: result.senderId?.isNotEmpty == true
                    ? result.senderId
                    : local.senderId,
                status: MessageStatus.sent,
                clearSendError: true,
              );
        await _database.confirmPendingMessage(clientMessageId, confirmed);
        _clearUploadStates(clientMessageId);
        result = confirmed;
      } catch (_) {
        throw const PendingMessageConfirmationException(
          '服务器已接收，本地状态保存失败，将自动修复',
        );
      }
      return result.copyWith(
        clientMsgId: clientMessageId,
        status: MessageStatus.sent,
        clearSendError: true,
      );
    } on PendingMessageConfirmationException {
      rethrow;
    } on PendingAttachmentUploadPausedException {
      rethrow;
    } catch (error) {
      await _markFailedWithoutBlockingUi(
        clientMessageId,
        pendingMessageErrorText(error),
      );
      rethrow;
    } finally {
      _activeClientMessageIds.remove(clientMessageId);
    }
  }

  Future<void> _markFailedWithoutBlockingUi(
    String clientMessageId,
    String error,
  ) async {
    try {
      await _database
          .markPendingMessageFailed(clientMessageId, error)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _clearUploadStates(String clientMessageId) {
    final prefix = '$clientMessageId:';
    _uploadStates.removeWhere((key, _) => key.startsWith(prefix));
    _activeUploadTokens.removeWhere((key, _) => key.startsWith(prefix));
    _activeUploadItems.removeWhere((key, _) => key.startsWith(prefix));
    _pausedUploads.removeWhere((key) => key.startsWith(prefix));
  }

  Future<MessageModel> _dispatch(PendingMessageRecord record) async {
    var payload = record.payload;
    if (payload['kind'] == 'attachment_upload' ||
        payload['kind'] == 'attachment_group_upload') {
      payload = await _uploadPendingAttachment(record, payload);
    }
    final replyMessageId = payload['reply_message_id']?.toString();
    if (payload['kind'] == 'text') {
      return _repository.sendText(
        conversationId: record.conversationId,
        clientMsgId: record.clientMessageId,
        bodyText: payload['body_text']?.toString() ?? '',
        replyMessageId: replyMessageId,
      );
    }

    final attachments = <MessageAttachmentDto>[];
    final rawAttachments = payload['attachments'];
    if (rawAttachments is List) {
      for (final item in rawAttachments.whereType<Map>()) {
        attachments.add(
          MessageAttachmentDto.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }
    return _repository.sendRichMessage(
      conversationId: record.conversationId,
      clientMsgId: record.clientMessageId,
      messageType: payload['message_type']?.toString() ?? 'text',
      attachments: attachments,
      replyMessageId: replyMessageId,
    );
  }

  Future<Map<String, dynamic>> _uploadPendingAttachment(
    PendingMessageRecord record,
    Map<String, dynamic> payload,
  ) async {
    var stored = await _database.readPendingAttachments(record.clientMessageId);
    if (stored.isEmpty) {
      throw const ApiException(
        code: 'LOCAL_ATTACHMENT_MISSING',
        message: '待上传附件已丢失',
      );
    }
    final rawItems = payload['items'] is List
        ? (payload['items'] as List)
        : <Object?>[
            {
              'index': 0,
              if (payload['width'] != null) 'width': payload['width'],
              if (payload['height'] != null) 'height': payload['height'],
              if (payload['duration_ms'] != null)
                'duration_ms': payload['duration_ms'],
              if (payload['waveform'] != null) 'waveform': payload['waveform'],
            },
          ];
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();

    // 旧版本待发送记录可能没有 items；恢复后立即统一为当前结构，使暂停状态、
    // Multipart 会话和 ETag 都有稳定的 SQLite 落点。
    payload['items'] = items;
    for (var position = 0; position < items.length; position++) {
      final item = items[position];
      item['index'] ??= position;
      final index = _int(item['index']) ?? position;
      final key = '${record.clientMessageId}:$index';
      _activeUploadItems[key] = item;
      if (item['upload_paused'] == true) {
        _pausedUploads.add(key);
        final original = _findAttachment(
          stored,
          _int(item['index']) ?? position,
          'original',
        );
        _publishPaused(
          record.clientMessageId,
          _int(item['index']) ?? position,
          original?.fileSize ?? 0,
        );
      }
    }

    Future<void> payloadWrite = Future<void>.value();
    Future<void> persistPayload() async {
      // 两个附件 worker 可能同时完成分片。串行取得最新内存快照再写 SQLite，
      // 避免较早的 JSON 覆盖另一个附件刚写入的 ETag 或用户暂停状态。
      final previous = payloadWrite;
      final gate = Completer<void>();
      payloadWrite = gate.future;
      await previous;
      try {
        final snapshot = jsonDecode(jsonEncode({...payload, 'items': items}));
        await _database.updatePendingPayload(
          record.clientMessageId,
          (snapshot as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      } finally {
        gate.complete();
      }
    }

    stored = await _database.readPendingAttachments(record.clientMessageId);

    Future<void> uploadItem(int position) async {
      final item = items[position];
      final index = _int(item['index']) ?? position;
      final key = '${record.clientMessageId}:$index';
      if (_pausedUploads.contains(key)) {
        final current = _uploadStates[key];
        if (current != null) {
          _publishUploadState(
            current.copyWith(phase: AttachmentUploadPhase.paused),
          );
        }
        return;
      }
      final original = _findAttachment(stored, index, 'original');
      if (original == null) {
        throw const ApiException(
          code: 'LOCAL_ATTACHMENT_MISSING',
          message: '待上传原文件已丢失',
        );
      }
      var resourceId = item['resource_id']?.toString() ?? '';
      if (resourceId.isEmpty) {
        try {
          final uploaded = await _uploadRecord(
            original,
            item: item,
            checkpointField: 'original_upload',
            persistPayload: persistPayload,
            publishProgress: true,
          );
          resourceId = uploaded.resourceId;
          item['resource_id'] = resourceId;
          item['resource_url'] = uploaded.url;
          item.remove('original_upload');
          item['upload_paused'] = false;
          _pausedUploads.remove(key);
          await persistPayload();
        } on MessageUploadPausedException {
          _publishPaused(record.clientMessageId, index, original.fileSize);
          return;
        }
      }

      _publishUploadState(
        AttachmentUploadProgressState(
          clientMessageId: record.clientMessageId,
          attachmentIndex: index,
          phase: AttachmentUploadPhase.processing,
          progress: 1,
          canPause: false,
        ),
      );
      final thumbnail = _findAttachment(stored, index, 'thumbnail');
      var thumbnailResourceId = item['thumbnail_resource_id']?.toString() ?? '';
      if (thumbnail != null && thumbnailResourceId.isEmpty) {
        final uploadedThumbnail = await _uploadRecord(
          thumbnail,
          item: item,
          checkpointField: 'thumbnail_upload',
          persistPayload: persistPayload,
          publishProgress: false,
        );
        thumbnailResourceId = uploadedThumbnail.resourceId;
        item['thumbnail_resource_id'] = thumbnailResourceId;
        item['thumbnail_url'] = uploadedThumbnail.url;
        item.remove('thumbnail_upload');
        await persistPayload();
      }
      _publishUploadState(
        AttachmentUploadProgressState(
          clientMessageId: record.clientMessageId,
          attachmentIndex: index,
          phase: AttachmentUploadPhase.completed,
          progress: 1,
          canPause: false,
        ),
      );
    }

    // 每轮最多两个 worker。若某项暂停，其他项继续；用户在同一轮完成前恢复
    // 时，下一轮会自动发现该项，不要求再次点击消息重试。
    while (true) {
      final candidates = <int>[];
      for (var position = 0; position < items.length; position++) {
        final item = items[position];
        final index = _int(item['index']) ?? position;
        final resourceId = item['resource_id']?.toString() ?? '';
        final originalPaused =
            resourceId.isEmpty &&
            _pausedUploads.contains('${record.clientMessageId}:$index');
        if (resourceId.isEmpty && !originalPaused) {
          candidates.add(position);
        }
      }
      if (candidates.isEmpty) break;
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < candidates.length) {
          final position = candidates[cursor++];
          await uploadItem(position);
        }
      }

      final count = candidates.length < 2 ? candidates.length : 2;
      await Future.wait(List.generate(count, (_) => worker()));
    }
    await payloadWrite;

    final attachments = <MessageAttachmentDto>[];
    for (var position = 0; position < items.length; position++) {
      final item = items[position];
      final index = _int(item['index']) ?? position;
      final original = _findAttachment(stored, index, 'original');
      final resourceId = item['resource_id']?.toString() ?? '';
      if (original == null || resourceId.isEmpty) {
        throw const PendingAttachmentUploadPausedException();
      }
      attachments.add(
        MessageAttachmentDto(
          resourceId: resourceId,
          url: item['resource_url']?.toString(),
          thumbnailResourceId: item['thumbnail_resource_id']?.toString(),
          thumbnailUrl: item['thumbnail_url']?.toString(),
          filename: original.filename,
          size: original.fileSize,
          mimeType: original.mimeType,
          width: _int(item['width']),
          height: _int(item['height']),
          durationMs: _int(item['duration_ms']),
          waveform: item['waveform'] is List
              ? (item['waveform'] as List)
                    .map((value) => double.tryParse(value.toString()) ?? 0)
                    .toList()
              : const [],
        ),
      );
    }
    final next = <String, dynamic>{
      'kind': 'rich',
      'message_type': payload['message_type']?.toString() ?? 'file',
      'attachments': attachments.map((item) => item.toJson()).toList(),
    };
    await _database.updatePendingPayload(record.clientMessageId, next);
    return next;
  }

  Future<MessageAttachmentDto> _uploadRecord(
    PendingAttachmentRecord stored, {
    required Map<String, dynamic> item,
    required String checkpointField,
    required Future<void> Function() persistPayload,
    required bool publishProgress,
  }) async {
    final bytes = await _attachmentStore.read(
      localPath: stored.localPath,
      storedBytes: stored.storedBytes,
    );
    final key = '${stored.clientMessageId}:${stored.attachmentIndex}';
    final rawCheckpoint = item[checkpointField];
    final checkpoint = rawCheckpoint is Map
        ? MessageUploadCheckpoint.fromJson(
            rawCheckpoint.map(
              (checkpointKey, value) =>
                  MapEntry(checkpointKey.toString(), value),
            ),
          )
        : null;
    final token = CancelToken();
    if (publishProgress) _activeUploadTokens[key] = token;
    var lastPercent = -1;
    try {
      return await _uploadRepository.uploadMessageFile(
        MessageUploadFile(
          filename: stored.filename,
          mimeType: stored.mimeType,
          bytes: bytes,
        ),
        checkpoint: checkpoint,
        cancelToken: publishProgress ? token : null,
        isPaused: publishProgress ? () => _pausedUploads.contains(key) : null,
        onCheckpoint: (next) async {
          item[checkpointField] = next.toJson();
          await persistPayload();
        },
        onFileProgress: publishProgress
            ? (progress) {
                final total = progress.total <= 0
                    ? stored.fileSize
                    : progress.total;
                final value = total <= 0
                    ? 0.0
                    : (progress.sent / total).clamp(0.0, 1.0);
                final percent = (value * 100).floor();
                // Dio 可能为一个分片产生大量回调；UI 每 1% 更新一次，避免 9 个
                // 媒体同时上传时反复重建聊天列表。
                if (percent == lastPercent && progress.sent < total) return;
                lastPercent = percent;
                _publishUploadState(
                  AttachmentUploadProgressState(
                    clientMessageId: stored.clientMessageId,
                    attachmentIndex: stored.attachmentIndex,
                    phase: AttachmentUploadPhase.uploading,
                    progress: value,
                    canPause: progress.mode == MessageUploadMode.multipart,
                  ),
                );
              }
            : null,
      );
    } finally {
      if (publishProgress && identical(_activeUploadTokens[key], token)) {
        _activeUploadTokens.remove(key);
      }
    }
  }

  void _publishPaused(String clientMessageId, int index, int fileSize) {
    final key = '$clientMessageId:$index';
    final current = _uploadStates[key];
    _publishUploadState(
      current?.copyWith(phase: AttachmentUploadPhase.paused, canPause: true) ??
          AttachmentUploadProgressState(
            clientMessageId: clientMessageId,
            attachmentIndex: index,
            phase: AttachmentUploadPhase.paused,
            progress: 0,
            canPause: fileSize > 20 * 1024 * 1024,
          ),
    );
  }
}

int? _int(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

PendingAttachmentRecord? _findAttachment(
  List<PendingAttachmentRecord> records,
  int index,
  String role,
) {
  for (final record in records) {
    if (record.attachmentIndex == index && record.role == role) return record;
  }
  return null;
}

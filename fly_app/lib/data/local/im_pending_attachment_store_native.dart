/// 原生平台把待上传附件复制到应用私有目录，避免系统选择器临时 URI 失效。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'im_pending_attachment_store_contract.dart';

ImPendingAttachmentStore createImPendingAttachmentStore() =>
    const _NativePendingAttachmentStore();

class _NativePendingAttachmentStore implements ImPendingAttachmentStore {
  const _NativePendingAttachmentStore();

  @override
  Future<StagedPendingAttachment> stage({
    required String userId,
    required String storageKey,
    required List<int> bytes,
    String? sourcePath,
  }) async {
    final root = await getApplicationSupportDirectory();
    final accountKey = base64Url
        .encode(utf8.encode(userId))
        .replaceAll('=', '');
    final directory = Directory('${root.path}/im_pending/$accountKey');
    await directory.create(recursive: true);
    final safeKey = storageKey.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final file = File('${directory.path}/$safeKey.bin');
    try {
      final sourceValue = sourcePath?.trim();
      final source = sourceValue == null || sourceValue.isEmpty
          ? null
          : File(sourceValue);
      if (source != null && await source.exists()) {
        // 大视频直接由文件流写入私有待发送目录，禁止先把整个文件读进 Dart
        // 堆内存。流式复制也避免了“读取一次、写入一次”的双倍等待。
        final sink = file.openWrite(mode: FileMode.writeOnly);
        try {
          await sink.addStream(source.openRead());
          await sink.flush();
        } finally {
          await sink.close();
        }
      } else {
        await file.writeAsBytes(bytes, flush: true);
      }
      return StagedPendingAttachment(localPath: file.path);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  @override
  Future<List<int>> read({String? localPath, Object? storedBytes}) async {
    if (localPath == null || localPath.isEmpty) {
      throw StateError('待上传附件缺少本地路径');
    }
    return File(localPath).readAsBytes();
  }

  @override
  Future<void> delete(String? localPath) async {
    if (localPath == null || localPath.isEmpty) return;
    final file = File(localPath);
    if (await file.exists()) await file.delete();
  }
}

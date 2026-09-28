/// 待上传附件的跨平台暂存契约。
library;

import 'dart:typed_data';

/// 原生平台返回 [localPath]，Web 返回待写入 SQLite BLOB 的 [bytes]。
class StagedPendingAttachment {
  const StagedPendingAttachment({this.localPath, this.bytes});

  final String? localPath;
  final Uint8List? bytes;
}

abstract interface class ImPendingAttachmentStore {
  Future<StagedPendingAttachment> stage({
    required String userId,
    required String storageKey,
    required List<int> bytes,
    String? sourcePath,
  });

  Future<List<int>> read({String? localPath, Object? storedBytes});

  Future<void> delete(String? localPath);
}

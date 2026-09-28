/// Web 平台把附件字节交给 SQLite WASM，以 BLOB 形式持久化到 IndexedDB。
library;

import 'dart:typed_data';

import 'im_pending_attachment_store_contract.dart';

ImPendingAttachmentStore createImPendingAttachmentStore() =>
    const _WebPendingAttachmentStore();

class _WebPendingAttachmentStore implements ImPendingAttachmentStore {
  const _WebPendingAttachmentStore();

  @override
  Future<StagedPendingAttachment> stage({
    required String userId,
    required String storageKey,
    required List<int> bytes,
    String? sourcePath,
  }) async => StagedPendingAttachment(bytes: Uint8List.fromList(bytes));

  @override
  Future<List<int>> read({String? localPath, Object? storedBytes}) async {
    if (storedBytes is Uint8List) return storedBytes;
    if (storedBytes is List<int>) return storedBytes;
    if (storedBytes is List) return storedBytes.cast<int>();
    throw StateError('待上传附件 BLOB 已丢失');
  }

  @override
  Future<void> delete(String? localPath) async {}
}

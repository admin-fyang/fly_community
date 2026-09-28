// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

/// Web 端把 SQLite BLOB 转换为临时 Blob URL，并在播放器切换时回收。
library;

import 'dart:html' as html;
import 'dart:typed_data';

import 'local_media_source_contract.dart';

LocalMediaSource createLocalMediaSource() => const _WebLocalMediaSource();

class _WebLocalMediaSource implements LocalMediaSource {
  const _WebLocalMediaSource();

  @override
  LocalMediaHandle? create({String? path, List<int>? bytes, String? mimeType}) {
    final existing = path?.trim();
    if (existing != null && existing.isNotEmpty) {
      // FilePicker 的 XFile 在 Web 上可能已经提供 Blob URL；它的生命周期由
      // 选择器管理，本服务不越权回收。
      return LocalMediaHandle(existing);
    }
    if (bytes == null || bytes.isEmpty) return null;
    final blob = html.Blob(
      <Object>[Uint8List.fromList(bytes)],
      mimeType?.trim().isEmpty == false ? mimeType : 'application/octet-stream',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    return LocalMediaHandle(url, () => html.Url.revokeObjectUrl(url));
  }
}

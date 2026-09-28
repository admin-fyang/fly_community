// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

/// Web 交给浏览器下载，不尝试自动打开本地文件。
library;

import 'dart:html' as html;

import 'file_transfer_service_contract.dart';

FileTransferService createFileTransferService() =>
    const _WebFileTransferService();

class _WebFileTransferService implements FileTransferService {
  const _WebFileTransferService();

  @override
  Future<String?> download({
    required String url,
    required String resourceId,
    required String filename,
    TransferProgress? onProgress,
  }) async {
    _trigger(url, filename);
    return null;
  }

  @override
  Future<void> open(String localPath) async {
    throw UnsupportedError('Web 文件由浏览器管理');
  }

  @override
  Future<void> saveMedia({
    required String url,
    required String filename,
    required bool isVideo,
    TransferProgress? onProgress,
  }) async => _trigger(url, filename);

  void _trigger(String url, String filename) {
    final anchor =
        html.AnchorElement(href: url)
          ..download = filename
          ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }
}

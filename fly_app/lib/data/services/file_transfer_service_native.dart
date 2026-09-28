/// Android 等原生平台的附件下载、媒体保存与系统打开实现。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'file_transfer_service_contract.dart';

FileTransferService createFileTransferService() => _NativeFileTransferService();

class _NativeFileTransferService implements FileTransferService {
  _NativeFileTransferService() : _dio = Dio();
  final Dio _dio;

  @override
  Future<String> download({
    required String url,
    required String resourceId,
    required String filename,
    TransferProgress? onProgress,
  }) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/downloads/${_safe(resourceId)}');
    await directory.create(recursive: true);
    final target = File('${directory.path}/${_safe(filename)}');
    if (await target.exists() && await target.length() > 0) return target.path;
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
    try {
      await _dio.download(url, partial.path, onReceiveProgress: onProgress);
      if (await target.exists()) await target.delete();
      return (await partial.rename(target.path)).path;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  @override
  Future<void> open(String localPath) async {
    final result = await OpenFilex.open(localPath);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  @override
  Future<void> saveMedia({
    required String url,
    required String filename,
    required bool isVideo,
    TransferProgress? onProgress,
  }) async {
    if (!isVideo) {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw StateError('图片数据为空');
      await ImageGallerySaverPlus.saveImage(
        Uint8List.fromList(bytes),
        name: _safe(filename),
      );
      return;
    }
    final root = await getTemporaryDirectory();
    final temporary = File(
      '${root.path}/${DateTime.now().microsecondsSinceEpoch}_${_safe(filename)}',
    );
    try {
      await _dio.download(url, temporary.path, onReceiveProgress: onProgress);
      await ImageGallerySaverPlus.saveFile(
        temporary.path,
        name: _safe(filename),
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _safe(String value) {
    final normalized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return normalized.isEmpty ? 'attachment' : normalized;
  }
}

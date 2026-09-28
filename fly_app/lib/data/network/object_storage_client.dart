/// 对象存储直传客户端。
///
/// 使用独立 Dio 实例，不安装认证拦截器，避免向预签名地址泄露 Bearer Token。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';

class ObjectStorageClient {
  ObjectStorageClient(Dio dio) : _dio = dio;

  final Dio _dio;

  Future<String?> put({
    required String uploadUrl,
    required Map<String, String> headers,
    required Uint8List bytes,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.putUri<Object?>(
        Uri.parse(uploadUrl),
        data: bytes,
        options: Options(
          headers: {
            ...headers,
            Headers.contentLengthHeader: bytes.lengthInBytes,
          },
          responseType: ResponseType.plain,
        ),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      return response.headers.value('etag');
    } on DioException catch (error) {
      final message = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => '文件上传超时，请重试',
        DioExceptionType.connectionError => '无法连接文件存储服务',
        DioExceptionType.cancel => '文件上传已暂停',
        _ => '文件上传失败，请重试',
      };
      throw ApiException(
        code: error.type == DioExceptionType.cancel
            ? 'STORAGE_UPLOAD_PAUSED'
            : 'STORAGE_UPLOAD_FAILED',
        message: message,
        statusCode: error.response?.statusCode,
      );
    } on FormatException {
      throw const ApiException(code: 'INVALID_UPLOAD_URL', message: '文件上传地址无效');
    }
  }
}

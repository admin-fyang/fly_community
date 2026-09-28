/// 后端统一响应结构。
library;

import 'api_exception.dart';

typedef DataDecoder<T> = T Function(Object? data);

class BaseResponse<T> {
  const BaseResponse({
    required this.code,
    required this.message,
    required this.data,
    this.requestId,
  });

  final String code;
  final String message;
  final T data;
  final String? requestId;

  /// 解析统一响应，并在结构异常或业务码非 OK 时抛出可追踪异常。
  factory BaseResponse.fromJson(
    Map<String, dynamic> json,
    DataDecoder<T> decodeData, {
    int? statusCode,
  }) {
    try {
      final code = json['code'];
      final message = json['message'];
      final requestId = json['request_id'];
      if (code is! String || message is! String) {
        throw const FormatException('统一响应缺少 code 或 message');
      }
      if (code != 'OK') {
        throw ApiException(
          code: code,
          message: message,
          statusCode: statusCode,
          requestId: requestId is String ? requestId : null,
        );
      }
      return BaseResponse<T>(
        code: code,
        message: message,
        data: decodeData(json['data']),
        requestId: requestId is String ? requestId : null,
      );
    } on ApiException {
      rethrow;
    } on FormatException catch (error) {
      throw ApiException(
        code: 'INVALID_RESPONSE',
        message: error.message,
        statusCode: statusCode,
        requestId:
            json['request_id'] is String ? json['request_id'] as String : null,
      );
    } catch (_) {
      throw ApiException(
        code: 'INVALID_RESPONSE',
        message: '服务器响应格式不正确',
        statusCode: statusCode,
        requestId:
            json['request_id'] is String ? json['request_id'] as String : null,
      );
    }
  }
}

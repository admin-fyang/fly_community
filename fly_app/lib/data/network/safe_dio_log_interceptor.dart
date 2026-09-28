/// HTTP 诊断只输出经过类型验证的白名单摘要；debug 日志也不得携带用户内容。
/// 保留链路标识、状态和耗时，不序列化正文、任意字段、异常文本或上传文件名。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/utils/log_util.dart';

class SafeDioLogInterceptor extends Interceptor {
  static const _startedAtKey = 'safe_log_started_at';
  static final _requestIdPattern = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    LogUtil.d(
      'request ${options.method} ${_requestTarget(options)} '
      'query=${_render(options.queryParameters)} '
      'data=${_render(options.data)}',
      tag: 'HTTP',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final requestId = _requestId(response.data);
    LogUtil.d(
      '${response.requestOptions.method} '
      '${_requestTarget(response.requestOptions)} '
      'status=${response.statusCode ?? '-'} '
      'duration=${_elapsedMilliseconds(response.requestOptions)}ms'
      '${requestId == null ? '' : ' request_id=$requestId'} '
      'response=${_render(response.data)}',
      tag: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final requestId = _requestId(err.response?.data);
    LogUtil.d(
      '${err.requestOptions.method} ${_requestTarget(err.requestOptions)} '
      'failed type=${err.type.name} '
      'retry_count=${err.requestOptions.extra['retry_count'] ?? 0} '
      'status=${err.response?.statusCode ?? '-'} '
      'duration=${_elapsedMilliseconds(err.requestOptions)}ms'
      '${requestId == null ? '' : ' request_id=$requestId'} '
      'response=${_render(err.response?.data)}',
      tag: 'HTTP',
    );
    handler.next(err);
  }

  /// 输出实际请求来源与路径，但不记录查询参数，避免签名 URL 泄露密钥。
  String _requestTarget(RequestOptions options) {
    final uri = options.uri;
    if (!uri.hasAuthority) return uri.path;
    final defaultPort =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    final port = defaultPort ? '' : ':${uri.port}';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  int _elapsedMilliseconds(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return 0;
    return ((DateTime.now().microsecondsSinceEpoch - startedAt) / 1000).round();
  }

  String? _requestId(Object? data) {
    if (data is! Map) return null;
    final value = data['request_id'];
    return value is String && _requestIdPattern.hasMatch(value) ? value : null;
  }

  /// 未知字段默认丢弃，只沿 API 固定容器读取诊断字段。
  /// 不输出未知键名、字符串、对象 toString 或上传文件元数据。
  String _render(Object? value) => jsonEncode(_summary(value));

  Map<String, Object> _summary(Object? value, {int depth = 0}) {
    if (depth > 4) return {'truncated': true};
    if (value is FormData) {
      return {'field_count': value.fields.length, 'file_count': value.files.length};
    }
    if (value is MultipartFile) return {'upload_bytes': value.length};
    if (value is List) {
      return {
        'count': value.length,
        'items': value.take(20).map((item) => _summary(item, depth: depth + 1)).toList(),
      };
    }
    if (value is! Map) return {'redacted': value != null};
    final safe = <String, Object>{};
    for (final key in const [
      'message_id', 'conversation_id', 'group_id', 'user_id', 'event_id',
      'outbox_id', 'limit', 'count', 'viewer_count', 'seq',
    ]) {
      final item = value[key];
      if (item is int && item >= 0) {
        safe[key] = item;
      } else if (item is String && RegExp(r'^[0-9]{1,20}$').hasMatch(item)) {
        safe[key] = item;
      }
    }
    final requestId = _requestId(value);
    if (requestId != null) safe['request_id'] = requestId;
    final body = value['body_text'];
    if (body is String) safe['body_length'] = utf8.encode(body).length;
    for (final key in const ['data', 'items', 'messages', 'message', 'events']) {
      final child = value[key];
      if (child is Map || child is List) {
        safe[key] = _summary(child, depth: depth + 1);
      }
    }
    return safe;
  }
}

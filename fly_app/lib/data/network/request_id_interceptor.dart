/// 请求链路标识拦截器。
///
/// 每次 HTTP 业务请求生成独立 UUID v4，并通过 `X-Request-ID` 发送给后端，
/// 便于客户端错误提示、脱敏日志与服务端日志关联。业务幂等键不复用此值。
library;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class RequestIdInterceptor extends Interceptor {
  RequestIdInterceptor({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent('X-Request-ID', _uuid.v4);
    handler.next(options);
  }
}

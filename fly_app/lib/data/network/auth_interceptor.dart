/// 认证请求拦截器。
library;

import 'package:dio/dio.dart';

import '../local/session_storage.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage, {
    Future<void> Function()? onUnauthorized,
    this.onSessionUnauthorized,
  })
    : _onUnauthorized = onUnauthorized;

  /// 携带请求发起时的会话 ID 和服务端原因，避免清理新登录。
  final Future<void> Function(String sessionId, String reason)? onSessionUnauthorized;
  final SessionStorage _storage;
  final Future<void> Function()? _onUnauthorized;
  bool _handlingUnauthorized = false;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['Accept'] = 'application/json';
    if (options.extra['requires_auth'] != false) {
      final identity = onSessionUnauthorized == null
          ? null : await _storage.readAuthIdentity();
      final token = identity == null
          ? await _storage.readAccessToken() : identity.token;
      // 重试必须沿用请求发起时的身份；在真正注入认证头前再次校验，
      // 关闭 ApiClient 检查与异步读取凭证之间的账号切换窗口。
      if (options.extra.containsKey('expected_auth_token') &&
          options.extra['expected_auth_token'] != token) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: '登录状态已变化',
          ),
        );
        return;
      }
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
        if (onSessionUnauthorized != null) {
          options.extra['auth_session_id'] = identity?.sessionId;
        }
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final requiresAuth = err.requestOptions.extra['requires_auth'] != false;
    if (statusCode == 401 && requiresAuth) {
      final token = await _storage.readAccessToken();
      // 旧凭证的迟到 401 不得清除已经建立的新会话。
      if (err.requestOptions.headers['Authorization'] == 'Bearer $token') {
        final sessionId = err.requestOptions.extra['auth_session_id'];
        final body = err.response?.data;
        final reason = body is Map && body['code'] is String
            ? body['code'] as String : 'AUTH_TOKEN_INVALID';
        if (onSessionUnauthorized != null && sessionId is String) {
          // 协调器按会话合并并发回调。认证失败仍交给 Dio 的原处理链。
          onSessionUnauthorized!(sessionId, reason).ignore();
        } else {
          _handleUnauthorized();
        }
      }
    }
    handler.next(err);
  }

  /// 401 的语义是“当前凭证已不可继续使用”。
  /// 网络层只负责触发全局失效回调，具体清会话和路由跳转由 App 装配层决定。
  void _handleUnauthorized() {
    final callback = _onUnauthorized;
    if (callback == null || _handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      callback().whenComplete(() => _handlingUnauthorized = false);
    } catch (_) {
      _handlingUnauthorized = false;
    }
  }
}

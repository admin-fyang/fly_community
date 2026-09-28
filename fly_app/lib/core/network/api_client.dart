/// Dio API 客户端。
///
/// 统一负责请求、BaseResponse 解析和 Dio 异常转换，不向页面暴露 DioException。
library;

import 'dart:async';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'base_response.dart';
import 'network_recovery_controller.dart';

class ApiClient {
  const ApiClient(
    this._dio, {
    this.readAccessToken,
    this.retryDelay,
    this.recovery,
  });

  /// 由装配层提供凭证读取，防止查询在重试期间跨账号执行。
  final Future<String?> Function()? readAccessToken;

  /// 测试可注入等待器；生产使用真实退避，总计最多三次请求（首次请求加两次重试）。
  final Future<void> Function(Duration)? retryDelay;
  static const _retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 2),
  ];

  final Dio _dio;
  final NetworkRecoveryController? recovery;

  Future<T> get<T>(
    String path, {
    required DataDecoder<T> decoder,
    bool requiresAuth = true,
    bool retry = true,
    CancelToken? cancelToken,
  }) {
    return _request<T>(
      path,
      method: 'GET',
      retry: retry,
      cancelToken: cancelToken,
      decoder: decoder,
      requiresAuth: requiresAuth,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    required DataDecoder<T> decoder,
    bool requiresAuth = true,
  }) {
    return _request<T>(
      path,
      method: 'POST',
      data: data,
      decoder: decoder,
      requiresAuth: requiresAuth,
    );
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    required DataDecoder<T> decoder,
    bool requiresAuth = true,
  }) {
    return _request<T>(
      path,
      method: 'PUT',
      data: data,
      decoder: decoder,
      requiresAuth: requiresAuth,
    );
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    required DataDecoder<T> decoder,
    bool requiresAuth = true,
  }) {
    return _request<T>(
      path,
      method: 'PATCH',
      data: data,
      decoder: decoder,
      requiresAuth: requiresAuth,
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? data,
    required DataDecoder<T> decoder,
    bool requiresAuth = true,
  }) {
    return _request<T>(
      path,
      method: 'DELETE',
      data: data,
      decoder: decoder,
      requiresAuth: requiresAuth,
    );
  }

  /// 调用 data 为空对象的接口，例如退出登录。
  Future<void> postEmpty(
    String path, {
    Object? data,
    bool requiresAuth = true,
  }) async {
    await _request<Object?>(
      path,
      method: 'POST',
      data: data,
      decoder: (_) => null,
      requiresAuth: requiresAuth,
    );
  }

  Future<T> _request<T>(
    String path, {
    required String method,
    Object? data,
    required DataDecoder<T> decoder,
    required bool requiresAuth,
    bool retry = false,
    CancelToken? cancelToken,
  }) async {
    final recoveryKey = '$method $path';
    final recoveryGeneration = recovery?.sessionGeneration;
    final recoveryRevision = recovery?.beginQuery(recoveryKey);
    final sessionToken = requiresAuth ? await readAccessToken?.call() : null;
    void checkCancelled() {
      if (cancelToken?.isCancelled == true) {
        throw const ApiException(
          code: 'REQUEST_CANCELLED',
          kind: ApiFailureKind.cancelled,
          message: '请求已取消',
        );
      }
    }

    Future<void> checkSession() async {
      checkCancelled();
      if (requiresAuth &&
          readAccessToken != null &&
          await readAccessToken!() != sessionToken) {
        throw const ApiException(
          code: 'REQUEST_CANCELLED',
          kind: ApiFailureKind.cancelled,
          message: '登录状态已变化，请求已取消',
        );
      }
    }

    for (var attempt = 0; ; attempt++) {
      try {
        await checkSession();
        final response = await _dio.request<Object?>(
          path,
          data: data,
          cancelToken: cancelToken,
          options: Options(
            method: method,
            // Dio Web 无法对没有请求体的请求应用发送超时。显式使用 zero
            // 覆盖全局值，消除 GET、空 POST 等请求的无效告警；有请求体时
            // 继续继承 BaseOptions 中的发送超时。
            sendTimeout: data == null ? Duration.zero : null,
            extra: {
              'requires_auth': requiresAuth,
              'retry_count': attempt,
              if (requiresAuth && readAccessToken != null)
                'expected_auth_token': sessionToken,
            },
          ),
        );
        await checkSession();
        final body = _asJsonObject(response.data);
        final result = BaseResponse<T>.fromJson(
          body,
          decoder,
          statusCode: response.statusCode,
        ).data;
        recovery?.querySucceeded(
          recoveryKey,
          generation: recoveryGeneration,
          revision: recoveryRevision,
        );
        return result;
      } on ApiException {
        recovery?.querySucceeded(
          recoveryKey,
          generation: recoveryGeneration,
          revision: recoveryRevision,
        );
        rethrow;
      } on DioException catch (error) {
        try {
          await checkSession();
        } on ApiException {
          recovery?.querySucceeded(
            recoveryKey,
            generation: recoveryGeneration,
            revision: recoveryRevision,
          );
          rethrow;
        }
        if (!retry ||
            method != 'GET' ||
            attempt >= _retryDelays.length ||
            !_canRetry(error)) {
          if (retry && method == 'GET' && _canRetry(error)) {
            recovery?.queryFailed(
              recoveryKey,
              () async {
                try {
                  await checkSession();
                } on ApiException {
                  recovery?.querySucceeded(
                    recoveryKey,
                    generation: recoveryGeneration,
                    revision: recoveryRevision,
                  );
                  rethrow;
                }
                await _request<T>(
                  path,
                  method: method,
                  data: data,
                  decoder: decoder,
                  requiresAuth: requiresAuth,
                  retry: retry,
                  cancelToken: cancelToken,
                );
              },
              generation: recoveryGeneration,
              revision: recoveryRevision,
            );
          } else {
            recovery?.querySucceeded(
              recoveryKey,
              generation: recoveryGeneration,
              revision: recoveryRevision,
            );
            if (_canRetry(error)) {
              // 写入失败只反馈连接异常，恢复按钮绝不重放该写入。
              recovery?.connectionResult(false, generation: recoveryGeneration);
            }
          }
          throw _fromDio(error);
        }
        await checkSession();
        final wait = (retryDelay ?? Future<void>.delayed)(
          _retryDelays[attempt],
        );
        // 取消令牌完成后立即退出等待，下一轮发送前仍再次校验。
        if (cancelToken == null) {
          await wait;
        } else {
          await Future.any<void>([wait, cancelToken.whenCancel.then((_) {})]);
        }
      } catch (_) {
        recovery?.querySucceeded(
          recoveryKey,
          generation: recoveryGeneration,
          revision: recoveryRevision,
        );
        throw const ApiException(code: 'CLIENT_ERROR', message: '客户端处理请求时发生错误');
      }
    }
  }

  /// 只识别明确的瞬时传输/服务端故障，业务与解析异常不会进入此分支。
  bool _canRetry(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.badResponse => const {
      500,
      502,
      503,
      504,
    }.contains(error.response?.statusCode),
    _ => false,
  };

  Map<String, dynamic> _asJsonObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: '服务器未返回 JSON 对象',
    );
  }

  ApiException _fromDio(DioException error) {
    final response = error.response;
    final kind = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => ApiFailureKind.timeout,
      DioExceptionType.connectionError => ApiFailureKind.connection,
      DioExceptionType.cancel => ApiFailureKind.cancelled,
      DioExceptionType.badCertificate => ApiFailureKind.certificate,
      DioExceptionType.badResponse => ApiFailureKind.http,
      _ => ApiFailureKind.other,
    };
    final data = response?.data;
    final fallback = switch (response?.statusCode) {
      401 => '登录已失效，请重新登录',
      403 => '没有权限执行此操作',
      404 => '请求的数据不存在',
      422 => '提交的参数不正确',
      429 => '请求过于频繁，请稍后重试',
      final int status when status >= 500 => '服务器暂时不可用，请稍后重试',
      _ => '请求失败，请稍后重试',
    };
    if (data is Map) {
      final json = data.map((key, value) => MapEntry(key.toString(), value));
      return ApiException(
        kind: kind,
        code: json['code'] is String ? json['code'] as String : 'HTTP_ERROR',
        message: json['message'] is String
            ? json['message'] as String
            : fallback,
        statusCode: response?.statusCode,
        requestId: json['request_id'] is String
            ? json['request_id'] as String
            : null,
      );
    }

    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '连接服务器超时',
      DioExceptionType.connectionError => '无法连接服务器，请检查网络和 API 地址',
      DioExceptionType.cancel => '请求已取消',
      DioExceptionType.badCertificate => '服务器安全证书验证失败',
      DioExceptionType.badResponse => fallback,
      _ => '网络请求失败，请稍后重试',
    };
    return ApiException(
      kind: kind,
      code: switch (error.type) {
        DioExceptionType.cancel => 'REQUEST_CANCELLED',
        DioExceptionType.badCertificate => 'CERTIFICATE_ERROR',
        DioExceptionType.badResponse => 'HTTP_ERROR',
        _ => 'NETWORK_ERROR',
      },
      message: message,
      statusCode: response?.statusCode,
    );
  }
}

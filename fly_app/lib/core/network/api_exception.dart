/// API 统一异常。
///
/// 保留 HTTP 状态、稳定业务码和 request_id，便于 UI 提示及后端链路排查。
library;

/// 传输故障与业务码独立，调用方无需依赖中文错误文案判断恢复策略。
enum ApiFailureKind { timeout, connection, cancelled, certificate, http, other }

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.requestId,
    this.kind = ApiFailureKind.other,
  });

  final ApiFailureKind kind;
  final String code;
  final String message;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() => 'ApiException($code, $message, requestId: $requestId)';
}

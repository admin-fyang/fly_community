/// 验证码发送结果。
library;

class VerificationChallenge {
  const VerificationChallenge({
    required this.requestId,
    required this.expiresIn,
    required this.resendIn,
    required this.targetMasked,
    this.developmentCode,
  });

  final String requestId;
  final int expiresIn;
  final int resendIn;
  final String targetMasked;

  /// 仅开发环境后端显式开放时存在，生产环境必须为空。
  final String? developmentCode;

  factory VerificationChallenge.fromJson(Map<String, dynamic> json) {
    try {
      if (json['verification_request_id'] is! String ||
          json['expires_in'] is! int ||
          json['resend_in'] is! int ||
          json['target_masked'] is! String) {
        throw const FormatException('验证码响应缺少必填字段');
      }
      return VerificationChallenge(
        requestId: json['verification_request_id'] as String,
        expiresIn: json['expires_in'] as int,
        resendIn: json['resend_in'] as int,
        targetMasked: json['target_masked'] as String,
        developmentCode:
            json['verification_code'] is String
                ? json['verification_code'] as String
                : null,
      );
    } catch (_) {
      throw const FormatException('验证码响应格式不正确');
    }
  }
}

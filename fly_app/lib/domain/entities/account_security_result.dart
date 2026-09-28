/// 账号安全接口返回实体。
library;

class SessionRevocationResult {
  const SessionRevocationResult({
    required this.revokedSessionCount,
    this.currentSessionPreserved,
  });

  final int revokedSessionCount;
  final bool? currentSessionPreserved;

  factory SessionRevocationResult.fromJson(Map<String, dynamic> json) {
    final count = json['revoked_session_count'];
    if (count is! int) throw const FormatException('会话撤销结果格式不正确');
    return SessionRevocationResult(
      revokedSessionCount: count,
      currentSessionPreserved: json['current_session_preserved'] is bool
          ? json['current_session_preserved'] as bool
          : null,
    );
  }
}

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.status,
    this.effectiveAt,
    this.canCancelBefore,
  });

  final String status;
  final int? effectiveAt;
  final int? canCancelBefore;

  factory AccountDeletionResult.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status is! String || status.trim().isEmpty) {
      throw const FormatException('账号注销结果格式不正确');
    }
    return AccountDeletionResult(
      status: status,
      effectiveAt: json['effective_at'] is int
          ? json['effective_at'] as int
          : null,
      canCancelBefore: json['can_cancel_before'] is int
          ? json['can_cancel_before'] as int
          : null,
    );
  }
}

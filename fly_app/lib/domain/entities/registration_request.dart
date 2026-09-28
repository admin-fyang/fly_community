/// 新版注册请求的领域实体。
///
/// 注册页面只收集和校验资料；Data 层负责把该实体转换为服务端 JSON，避免
/// Widget 或 Controller 继续拼装旧版 channel/account 顶层参数。
library;

/// 单个联系方式的验证码证明。
final class RegistrationVerification {
  const RegistrationVerification({
    required this.target,
    required this.verificationRequestId,
    required this.code,
    this.countryCode,
  });

  /// 手机号或邮箱原始输入。
  final String target;
  final String verificationRequestId;
  final String code;

  /// 仅手机号验证使用的国际区号，例如 `+86`。
  final String? countryCode;
}

/// 注册事务所需的完整资料。
final class RegistrationRequest {
  const RegistrationRequest({
    required this.username,
    required this.nickname,
    required this.password,
    this.inviteCode,
    this.phoneVerification,
    this.emailVerification,
  });

  final String username;
  final String nickname;
  final String password;
  final String? inviteCode;
  final RegistrationVerification? phoneVerification;
  final RegistrationVerification? emailVerification;
}

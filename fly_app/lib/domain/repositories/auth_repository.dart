/// 认证仓储接口。
library;

import '../entities/auth_session.dart';
import '../entities/account_security_result.dart';
import '../entities/verification_challenge.dart';
import '../entities/registration_request.dart';

abstract interface class AuthRepository {
  Future<VerificationChallenge> requestVerificationCode({
    required String channel,
    required String target,
    String? regionCode,
    String? countryCode,
  });

  Future<VerificationChallenge> requestPasswordResetCode({
    required String channel,
    required String target,
    String? countryCode,
  });

  Future<SessionRevocationResult> resetPassword({
    required String channel,
    required String account,
    String? countryCode,
    required String verificationRequestId,
    required String code,
    required String newPassword,
  });

  /// 可用性结果仅用于即时反馈；注册接口的唯一约束仍是最终判定。
  Future<bool> isUsernameAvailable(String username);

  Future<AuthSession> register(RegistrationRequest request);

  Future<AuthSession> login({
    required String account,
    String? countryCode,
    required String password,
  });

  /// 撤销当前设备对应的服务端会话。
  Future<void> logout();
}

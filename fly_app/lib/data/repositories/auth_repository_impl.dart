/// 认证仓储实现。
library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/account_security_result.dart';
import '../../domain/entities/verification_challenge.dart';
import '../../domain/entities/registration_request.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/session_storage.dart';
import '../services/device_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(
    this._client,
    this._deviceService,
    this._sessionStorage,
  );

  final ApiClient _client;
  final DeviceService _deviceService;
  final SessionStorage _sessionStorage;

  @override
  Future<VerificationChallenge> requestVerificationCode({
    required String channel,
    required String target,
    String? regionCode,
    String? countryCode,
  }) {
    return _client.post<VerificationChallenge>(
      ApiPaths.verificationCodes,
      requiresAuth: false,
      data: {
        'scene': channel == 'phone' ? 'register_phone' : 'register_email',
        'channel': channel,
        'target': target,
        'country_code': countryCode,
        if (regionCode != null) 'region_code': regionCode,
      },
      decoder: (data) => VerificationChallenge.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<VerificationChallenge> requestPasswordResetCode({
    required String channel,
    required String target,
    String? countryCode,
  }) {
    return _client.post<VerificationChallenge>(
      ApiPaths.verificationCodes,
      requiresAuth: false,
      data: {
        'purpose': 'reset_password',
        'channel': channel,
        'target': target,
        if (countryCode != null) 'country_code': countryCode,
      },
      decoder: (data) => VerificationChallenge.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<SessionRevocationResult> resetPassword({
    required String channel,
    required String account,
    String? countryCode,
    required String verificationRequestId,
    required String code,
    required String newPassword,
  }) {
    return _client.post<SessionRevocationResult>(
      ApiPaths.passwordReset,
      requiresAuth: false,
      data: {
        'channel': channel,
        'account': account,
        if (countryCode != null) 'country_code': countryCode,
        'verification_request_id': verificationRequestId,
        'code': code,
        'new_password': newPassword,
      },
      decoder: (data) => SessionRevocationResult.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<bool> isUsernameAvailable(String username) {
    return _client.get<bool>(
      ApiPaths.usernameAvailability(username),
      requiresAuth: false,
      decoder: (data) {
        final json = _jsonObject(data);
        final available = json['available'];
        if (available is! bool) {
          throw const FormatException('用户名可用性响应缺少 available');
        }
        return available;
      },
    );
  }

  @override
  Future<AuthSession> register(RegistrationRequest request) async {
    final session = await _client.post<AuthSession>(
      ApiPaths.register,
      requiresAuth: false,
      data: {
        'username': request.username,
        'nickname': request.nickname,
        'password': request.password,
        if (request.inviteCode != null) 'invite_code': request.inviteCode,
        if (request.phoneVerification case final verification?)
          'phone_verification': {
            'phone': verification.target,
            'country_code': verification.countryCode,
            'verification_request_id': verification.verificationRequestId,
            'code': verification.code,
          },
        if (request.emailVerification case final verification?)
          'email_verification': {
            'email': verification.target,
            'verification_request_id': verification.verificationRequestId,
            'code': verification.code,
          },
        'device': await _deviceService.requestPayload(),
      },
      decoder: (data) => AuthSession.fromJson(_jsonObject(data)),
    );
    await _sessionStorage.saveSession(session);
    return session;
  }

  @override
  Future<AuthSession> login({
    required String account,
    String? countryCode,
    required String password,
  }) async {
    final session = await _client.post<AuthSession>(
      ApiPaths.passwordLogin,
      requiresAuth: false,
      data: {
        'account': account,
        if (countryCode != null) 'country_code': countryCode,
        'password': password,
        'device': await _deviceService.requestPayload(),
      },
      decoder: (data) => AuthSession.fromJson(_jsonObject(data)),
    );
    await _sessionStorage.saveSession(session);
    return session;
  }

  @override
  Future<void> logout() => _client.postEmpty(ApiPaths.logout);

  static Map<String, dynamic> _jsonObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const FormatException('data 必须为 JSON 对象');
  }
}

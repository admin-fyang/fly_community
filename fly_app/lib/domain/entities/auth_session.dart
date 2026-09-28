/// 登录或注册成功后返回的认证会话。
library;

import 'auth_user.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.accessTokenExpiresIn,
    required this.refreshToken,
    required this.refreshTokenExpiresIn,
    required this.sessionId,
    required this.user,
  });

  final String accessToken;
  final int accessTokenExpiresIn;
  final String refreshToken;
  final int refreshTokenExpiresIn;
  final String sessionId;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    try {
      final user = json['user'];
      if (json['access_token'] is! String ||
          json['refresh_token'] is! String ||
          json['session_id'] is! String ||
          json['access_token_expires_in'] is! int ||
          json['refresh_token_expires_in'] is! int ||
          user is! Map) {
        throw const FormatException('认证会话缺少必填字段');
      }
      return AuthSession(
        accessToken: json['access_token'] as String,
        accessTokenExpiresIn: json['access_token_expires_in'] as int,
        refreshToken: json['refresh_token'] as String,
        refreshTokenExpiresIn: json['refresh_token_expires_in'] as int,
        sessionId: json['session_id'] as String,
        user: AuthUser.fromJson(
          user.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    } catch (_) {
      throw const FormatException('认证会话格式不正确');
    }
  }
}

/// 登录会话本地存储。
///
/// Token 和当前用户摘要使用 shared_preferences 持久化；不记录密码、验证码等敏感输入。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';

class SessionStorage {
  SessionStorage({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _accessTokenKey = 'auth.access_token';
  static const _accessTokenExpiresAtKey = 'auth.access_token_expires_at';
  static const _refreshTokenKey = 'auth.refresh_token';
  static const _refreshTokenExpiresAtKey = 'auth.refresh_token_expires_at';
  static const _sessionIdKey = 'auth.session_id';
  static String _revokedSessionKey(String id) => 'auth.revoked_session.$id';
  final _sessionLock = Lock();
  static const _userKey = 'auth.user';
  static const _deviceIdKey = 'device.installation_id';
  static const _imSyncCursorKey = 'im.sync_cursor';
  static const _chatKeyboardHeightKey = 'ui.chat_keyboard_height';

  final Future<SharedPreferences> _preferences;

  /// 独立前台服务 Isolate 有自己的 SharedPreferences 缓存，读取会话前必须刷新。
  Future<void> reload() async => (await _preferences).reload();

  Future<void> saveSession(AuthSession session) => _sessionLock.synchronized(() async {
    final preferences = await _preferences;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await preferences.setString(_accessTokenKey, session.accessToken);
    await preferences.setInt(
      _accessTokenExpiresAtKey,
      now + session.accessTokenExpiresIn,
    );
    await preferences.setString(_refreshTokenKey, session.refreshToken);
    await preferences.setInt(
      _refreshTokenExpiresAtKey,
      now + session.refreshTokenExpiresIn,
    );
    await preferences.setString(_sessionIdKey, session.sessionId);
    await preferences.setString(_userKey, jsonEncode(session.user.toJson()));
  });

  /// 与登录写入共用锁，认证头和失效回调必须来自同一份身份快照。
  Future<({String? token, String? sessionId})> readAuthIdentity() =>
      _sessionLock.synchronized(() async {
        final preferences = await _preferences;
        return (token: preferences.getString(_accessTokenKey),
          sessionId: preferences.getString(_sessionIdKey));
      });

  /// 读取认证会话 ID，仅用于识别会话，不作为鉴权凭证。
  Future<String?> readSessionId() async =>
      (await _preferences).getString(_sessionIdKey);

  /// 后台 Isolate 仅写撤销标记，不删除凭证，避免误清主 Isolate 的新登录。
  Future<void> markSessionRevoked(String sessionId) async =>
      (await _preferences).setBool(_revokedSessionKey(sessionId), true);

  Future<bool> isSessionRevoked() async {
    final preferences = await _preferences;
    final sessionId = preferences.getString(_sessionIdKey);
    return sessionId != null &&
        preferences.getBool(_revokedSessionKey(sessionId)) == true;
  }

  /// 与登录保存共用锁，防止旧撤销事件在异步清理期间删除新凭证。
  Future<bool> clearSessionIfCurrent(String sessionId) =>
      _sessionLock.synchronized(() async {
        if (await readSessionId() != sessionId) return false;
        await _clearSession();
        return true;
      });

  Future<String?> readAccessToken() async =>
      (await _preferences).getString(_accessTokenKey);

  Future<bool> hasSession() async {
    final preferences = await _preferences;
    final token = await readAccessToken();
    final expiresAt = preferences.getInt(_accessTokenExpiresAtKey);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return !await isSessionRevoked() && token != null &&
        token.isNotEmpty &&
        expiresAt != null &&
        expiresAt > now;
  }

  Future<AuthUser?> readUser() async {
    final raw = (await _preferences).getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AuthUser.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(AuthUser user) async {
    await (await _preferences).setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<String?> readDeviceId() async =>
      (await _preferences).getString(_deviceIdKey);

  Future<void> saveDeviceId(String value) async {
    await (await _preferences).setString(_deviceIdKey, value);
  }

  Future<String> readImSyncCursor() async =>
      (await _preferences).getString(_imSyncCursorKey) ?? '0';

  Future<void> saveImSyncCursor(String value) async {
    await (await _preferences).setString(_imSyncCursorKey, value);
  }

  Future<double?> readChatKeyboardHeight() async =>
      (await _preferences).getDouble(_chatKeyboardHeightKey);

  Future<void> saveChatKeyboardHeight(double value) async {
    await (await _preferences).setDouble(_chatKeyboardHeightKey, value);
  }

  Future<void> clearSession() => _sessionLock.synchronized(_clearSession);

  Future<void> _clearSession() async {
    final preferences = await _preferences;
    final sessionId = preferences.getString(_sessionIdKey);
    await Future.wait([
      if (sessionId != null) preferences.remove(_revokedSessionKey(sessionId)),
      preferences.remove(_accessTokenKey),
      preferences.remove(_accessTokenExpiresAtKey),
      preferences.remove(_refreshTokenKey),
      preferences.remove(_refreshTokenExpiresAtKey),
      preferences.remove(_sessionIdKey),
      preferences.remove(_userKey),
    ]);
  }
}

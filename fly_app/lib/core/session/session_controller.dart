/// 全局登录会话状态。
library;

import 'package:get/get.dart';

import '../../data/local/session_storage.dart';
import '../../data/services/avatar_cache_service.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/user_profile.dart';

class SessionController extends GetxService {
  SessionController(this._storage);

  final SessionStorage _storage;
  final currentUser = Rxn<AuthUser>();
  final loginNotice = ''.obs;
  String? currentSessionId;
  /// 当前资料版本，用于拒绝旧终端事件覆盖新资料。
  final profileVersion = 0.obs;

  Future<bool> restore() async {
    if (await _storage.isSessionRevoked()) {
      loginNotice.value = '此设备已被退出，请重新登录';
      final id = await _storage.readSessionId();
      if (id != null) await _storage.clearSessionIfCurrent(id);
      return false;
    }
    if (!await _storage.hasSession()) return false;
    currentSessionId = await _storage.readSessionId();
    currentUser.value = await _storage.readUser();
    profileVersion.value = 0;
    return currentUser.value != null;
  }

  void acceptSession(AuthSession session) {
    currentSessionId = session.sessionId;
    loginNotice.value = '';
    currentUser.value = session.user;
    profileVersion.value = 0;
  }

  Future<void> updateFromProfile(UserProfile profile) async {
    if (profile.profileVersion < profileVersion.value) return;
    final user = AuthUser(
      id: profile.id,
      publicId: profile.publicId,
      name: profile.name,
      avatarUrl: profile.avatarUrl,
      username: profile.username,
      verified: profile.verified,
    );
    currentUser.value = user;
    profileVersion.value = profile.profileVersion;
    await _storage.saveUser(user);
  }

  /// 应用可靠同步事件中的完整资料快照；版本相同或更旧的事件幂等忽略。
  Future<void> applyProfileEvent(UserProfile profile) => updateFromProfile(profile);

  /// 失效回调只能清除它所属的会话，迟到事件不影响新的登录。
  Future<bool> clearIfCurrent(String sessionId) async {
    if (!await _storage.clearSessionIfCurrent(sessionId)) return false;
    if (currentSessionId != null && currentSessionId != sessionId) return false;
    currentSessionId = null;
    currentUser.value = null;
    profileVersion.value = 0;
    return true;
  }

  Future<void> clear() async {
    // 认证态优先清除，头像缓存清理异常不能保留已退出的登录状态。
    await _storage.clearSession();
    currentSessionId = null;
    currentUser.value = null;
    profileVersion.value = 0;
    await AvatarCacheService.empty();
  }
}

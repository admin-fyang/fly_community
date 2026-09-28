/// 当前用户资料可靠事件同步。
library;

import 'dart:async';

import '../../core/session/session_controller.dart';
import '../../domain/entities/user_profile.dart';
import 'im_sync_service.dart';

/// 将 HTTP Sync 与实时链路归约后的资料事件合并到全局会话。
class UserProfileSyncService {
  UserProfileSyncService(this._sync, this._session) {
    _subscription = _sync.appliedEvents.listen(_onEvent);
  }

  final ImSyncService _sync;
  final SessionController _session;
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  void _onEvent(Map<String, dynamic> event) {
    if (event['event_type']?.toString() != 'user_profile_updated') return;
    final payload = event['payload'];
    if (payload is! Map) return;
    final raw = payload['user'];
    if (raw is! Map) return;
    try {
      final json = <String, dynamic>{
        for (final entry in raw.entries)
          entry.key.toString(): entry.value,
      };
      final profile = UserProfile.fromJson(json);
      final currentId = _session.currentUser.value?.id;
      if (currentId == null || currentId != profile.id) return;
      unawaited(_session.applyProfileEvent(profile));
    } catch (_) {
      // 脏事件由同步协议层保留并上报，不能影响其它事件消费。
    }
  }

  void dispose() => _subscription.cancel();
}

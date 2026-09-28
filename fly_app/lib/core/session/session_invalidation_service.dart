/// HTTP、实时连接和 Android 后台共用的会话失效协调器。
///
/// 会话 ID 是清理的身份边界；同一会话并发失效只执行一次。每项资源独立
/// 清理，非关键插件异常不能阻止认证态清除。不在后台显示 Toast。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/local/session_storage.dart';
import 'session_controller.dart';

class SessionInvalidationService extends GetxService
    with WidgetsBindingObserver {
  SessionInvalidationService({
    required this.storage,
    required this.session,
    required this.cleanups,
    required this.navigateToLogin,
  });

  final SessionStorage storage;
  final SessionController session;
  final List<Future<void> Function()> cleanups;
  final void Function() navigateToLogin;
  final Map<String, Future<void>> _pending = {};

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> invalidate(
    String sessionId, {
    String reason = 'AUTH_SESSION_REVOKED',
  }) {
    final running = _pending[sessionId];
    if (running != null) return running;
    final task = _invalidate(sessionId, reason);
    _pending[sessionId] = task;
    task.whenComplete(() => _pending.remove(sessionId)).ignore();
    return task;
  }

  Future<void> _invalidate(String id, String reason) async {
    if (await storage.readSessionId() != id) return;
    // 标记使后台重复启动立即失效；仍保留 ID 供后续清理逐步校验。
    await storage.markSessionRevoked(id);
    for (final cleanup in cleanups) {
      if (await storage.readSessionId() != id) return;
      try {
        await cleanup();
      } catch (error) {
        debugPrint('[session] 失效资源清理失败：${error.runtimeType}');
      }
    }
    if (!await session.clearIfCurrent(id)) return;
    session.loginNotice.value = reason == 'AUTH_SESSION_REVOKED'
        ? '此设备已被退出，请重新登录'
        : '登录状态已失效，请重新登录';
    navigateToLogin();
  }

  /// 主 Isolate 暂停期间的撤销由后台持久化标记，回前台后可靠补处理。
  Future<void> checkPendingRevocation() async {
    await storage.reload();
    final id = await storage.readSessionId();
    if (id != null && await storage.isSessionRevoked()) await invalidate(id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkPendingRevocation());
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}

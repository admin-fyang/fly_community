/// 系统通知未读数的全局状态。
///
/// 侧边栏、通知列表和通知详情共用同一份权威计数，禁止各页面自行维护副本。
library;

import 'package:get/get.dart';

import '../../domain/repositories/notification_repository.dart';

class NotificationUnreadController extends GetxController {
  NotificationUnreadController(this._repository);

  final NotificationRepository _repository;
  final count = 0.obs;
  final isRefreshing = false.obs;
  final lastError = RxnString();

  Future<void>? _activeRefresh;

  /// 拉取服务端权威未读数；并发触发时复用同一个请求。
  Future<void> refreshCount() {
    final active = _activeRefresh;
    if (active != null) return active;
    final future = _refreshOnce();
    _activeRefresh = future;
    return future.whenComplete(() => _activeRefresh = null);
  }

  Future<void> _refreshOnce() async {
    isRefreshing.value = true;
    lastError.value = null;
    try {
      final value = await _repository.getUnreadCount();
      count.value = value < 0 ? 0 : value;
    } catch (_) {
      // 背景刷新失败时保留上一次可信数字，避免角标闪烁或误归零。
      lastError.value = '未读数刷新失败';
    } finally {
      isRefreshing.value = false;
    }
  }

  /// 单条未读通知成功标记已读后的即时反馈。
  void decrement() {
    if (count.value > 0) count.value--;
  }

  /// 登录退出或会话失效时清除上一账号的角标。
  void clear() {
    count.value = 0;
    lastError.value = null;
  }
}

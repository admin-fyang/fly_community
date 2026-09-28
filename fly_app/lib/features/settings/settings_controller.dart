/// 设置主页控制器。
///
/// 负责服务端退出当前设备会话；失败时保留本地 Token，允许用户重试。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_sizes.dart';
import '../../data/services/im_lifecycle_service.dart';
import '../../data/services/chat_viewport_state_store.dart';
import '../../data/services/public_link_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import '../notifications/notification_unread_controller.dart';

class SettingsController extends GetxController {
  SettingsController({
    AuthRepository? repository,
    SessionController? sessionController,
    ImLifecycleService? lifecycleService,
    PublicLinkService? publicLinkService,
  }) : _repository = repository ?? Get.find<AuthRepository>(),
       _sessionController = sessionController ?? Get.find<SessionController>(),
       _lifecycleService = lifecycleService ?? Get.find<ImLifecycleService>(),
       _publicLinkService = publicLinkService;

  final AuthRepository _repository;
  final SessionController _sessionController;
  final ImLifecycleService _lifecycleService;
  final PublicLinkService? _publicLinkService;
  final isLoggingOut = false.obs;

  Future<void> openPrivacyPolicy() =>
      _openPublicLink(PublicLinkType.privacyPolicy, '隐私政策');

  Future<void> _openPublicLink(PublicLinkType type, String label) async {
    final service = _publicLinkService ?? Get.find<PublicLinkService>();
    final result = await service.open(type);
    if (result == PublicLinkOpenResult.opened) return;
    AppToast.show(
      result == PublicLinkOpenResult.notConfigured
          ? '$label地址尚未配置'
          : '$label打开失败，请稍后重试',
    );
  }

  Future<void> logout() async {
    if (isLoggingOut.value) return;
    isLoggingOut.value = true;
    try {
      await _repository.logout();

      // 服务端会话撤销成功后已经无法回滚。后续本地清理必须彼此隔离：
      // 实时连接或缓存清理失败也不能阻止清除认证态和返回登录页。
      await _completeLocalLogout();
      Get.offAllNamed(AppRoutes.login);
    } on ApiException catch (error) {
      AppToast.show(error.message);
    } catch (_) {
      AppToast.show('退出登录失败，请检查网络后重试');
    } finally {
      isLoggingOut.value = false;
    }
  }

  /// 完成服务端退出后的本地收尾。
  ///
  /// 每个阶段独立兜底，确保最关键的会话清理不会被非关键资源释放打断。
  Future<void> _completeLocalLogout() async {
    await _runLogoutCleanup('停止 IM 会话', _lifecycleService.deactivateSession);

    if (Get.isRegistered<ChatViewportStateStore>()) {
      await _runLogoutCleanup('清理聊天窗口状态', () async {
        Get.find<ChatViewportStateStore>().clear();
      });
    }

    await _runLogoutCleanup('清理本地登录会话', _sessionController.clear);

    if (Get.isRegistered<NotificationUnreadController>()) {
      await _runLogoutCleanup('清理通知未读数', () async {
        Get.find<NotificationUnreadController>().clear();
      });
    }
  }

  Future<void> _runLogoutCleanup(
    String stage,
    Future<void> Function() cleanup,
  ) async {
    try {
      await cleanup();
    } catch (error, stackTrace) {
      debugPrint('[logout] $stage失败：$error');
      debugPrint('[logout] stack\n$stackTrace');
    }
  }
}

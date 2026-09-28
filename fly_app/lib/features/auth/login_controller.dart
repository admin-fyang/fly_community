/// 登录页控制器。
///
/// 负责表单校验、调用认证仓储并更新全局会话；Widget 只接收输入和渲染状态。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../data/services/im_lifecycle_service.dart';
import '../../data/services/system_time_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import '../notifications/notification_unread_controller.dart';

class LoginController extends GetxController {
  LoginController({
    AuthRepository? repository,
    SessionController? sessionController,
  }) : _repository = repository ?? Get.find<AuthRepository>(),
       _sessionController = sessionController ?? Get.find<SessionController>();

  final AuthRepository _repository;
  final SessionController _sessionController;

  final accountController = TextEditingController();
  final passwordController = TextEditingController();
  final isSubmitting = false.obs;

  RxString get loginNotice => _sessionController.loginNotice;

  Future<void> login() async {
    if (isSubmitting.value) return;
    final account = accountController.text.trim();
    final password = passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      AppToast.show('请输入账号和密码');
      return;
    }

    isSubmitting.value = true;
    try {
      final session = await _repository.login(
        account: account,
        countryCode: _looksLikePhone(account) ? 'CN' : null,
        password: password,
      );
      _sessionController.acceptSession(session);
      Get.offAllNamed(AppRoutes.conversations);
      unawaited(Get.find<NotificationUnreadController>().refreshCount());
      unawaited(_activateImAfterLogin());
    } on ApiException catch (error) {
      AppToast.show(error.message);
    } catch (_) {
      AppToast.show('登录失败，请稍后重试');
    } finally {
      isSubmitting.value = false;
    }
  }

  /// 认证与 IM 本地缓存是两个独立结果。
  ///
  /// Token 已成功签发并持久化后必须允许进入应用；SQLite/WASM 或首次同步失败
  /// 只影响消息补偿，由生命周期服务继续重试，不能伪装成“登录失败”。
  Future<void> _activateImAfterLogin() async {
    final result = await Get.find<ImLifecycleService>().activateSession();
    if (result.shouldWarnSync) {
      AppToast.warning('登录成功，消息同步暂时失败，将自动重试');
    }
  }

  /// 进入统一用户名注册流程；联系方式验证由系统配置在流程内动态决定。
  void goRegister() {
    final config = Get.find<SystemTimeService>();
    if (!config.canRegister) {
      AppToast.warning('注册功能已关闭');
      return;
    }
    Get.toNamed(AppRoutes.register);
  }

  /// 进入验证码重置流程；重置成功后仍停留在登录体系，要求重新认证。
  void forgotPassword() => Get.toNamed(AppRoutes.forgotPassword);

  bool _looksLikePhone(String value) =>
      RegExp(r'^[+\d][\d\s-]{5,}$').hasMatch(value);

  @override
  void onClose() {
    accountController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}

/// 修改密码表单控制器。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../domain/repositories/account_security_repository.dart';
import '../../shared/utils/app_toast.dart';

class ChangePasswordController extends GetxController {
  ChangePasswordController({AccountSecurityRepository? repository})
    : _repository = repository ?? Get.find<AccountSecurityRepository>();

  final AccountSecurityRepository _repository;
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final isSubmitting = false.obs;

  Future<void> submit() async {
    if (isSubmitting.value) return;
    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text;
    if (currentPassword.isEmpty || newPassword.isEmpty) {
      AppToast.warning('请输入当前密码和新密码');
      return;
    }
    if (newPassword != confirmPasswordController.text) {
      AppToast.warning('两次输入的新密码不一致');
      return;
    }
    if (currentPassword == newPassword) {
      AppToast.warning('新密码不能与当前密码相同');
      return;
    }

    isSubmitting.value = true;
    try {
      final result = await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      AppToast.success('密码修改成功，已撤销其他设备的 ${result.revokedSessionCount} 个会话');
      Get.back();
    } on ApiException catch (error) {
      AppToast.error(
        error.code == 'CURRENT_PASSWORD_INVALID' ? '当前密码错误' : error.message,
      );
    } catch (_) {
      AppToast.error('密码修改失败，请稍后重试');
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}

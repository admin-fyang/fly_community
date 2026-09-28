/// 账号注销表单控制器。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../domain/repositories/account_security_repository.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/app_dialog.dart';

class DeleteAccountController extends GetxController {
  DeleteAccountController({AccountSecurityRepository? repository})
    : _repository = repository ?? Get.find<AccountSecurityRepository>();

  final AccountSecurityRepository _repository;
  final passwordController = TextEditingController();
  final isSubmitting = false.obs;

  Future<void> submit() async {
    if (isSubmitting.value) return;
    final password = passwordController.text;
    if (password.isEmpty) {
      AppToast.warning('请输入当前密码');
      return;
    }
    final confirmed = await AppConfirmDialog.show(
      title: '申请注销账号',
      message: '提交后账号进入 30 天冷静期。冷静期结束后账号将被注销，是否继续？',
      confirmText: '申请注销',
      danger: true,
    );
    if (confirmed != true) return;

    isSubmitting.value = true;
    try {
      final result = await _repository.requestDeletion(
        currentPassword: password,
      );
      AppToast.success('注销申请已提交，可在 30 天冷静期内取消');
      Get.back(result: result);
    } on ApiException catch (error) {
      AppToast.error(
        error.code == 'CURRENT_PASSWORD_INVALID' ? '当前密码错误' : error.message,
      );
    } catch (_) {
      AppToast.error('注销申请提交失败，请稍后重试');
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    passwordController.dispose();
    super.onClose();
  }
}

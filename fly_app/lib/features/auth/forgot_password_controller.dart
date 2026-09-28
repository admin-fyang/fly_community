/// 找回密码页控制器。
///
/// 负责手机号/邮箱切换、验证码发送与倒计时、表单校验及密码重置。
/// Widget 只渲染响应式状态并转发用户事件。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../data/enums/register_mode.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/region_code_picker.dart';

class ForgotPasswordController extends GetxController {
  ForgotPasswordController({AuthRepository? repository})
    : _repository = repository ?? Get.find<AuthRepository>();

  final AuthRepository _repository;
  final mode = RegisterMode.phone.obs;
  final regionCode = 'CN'.obs;
  final accountController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final verificationRequestId = RxnString();
  final resendSeconds = 0.obs;
  final isSendingCode = false.obs;
  final isSubmitting = false.obs;
  Timer? _timer;

  void goLogin() => Get.back();

  void setMode(RegisterMode value) {
    if (mode.value == value) return;
    mode.value = value;
    accountController.clear();
    codeController.clear();
    verificationRequestId.value = null;
    _stopCountdown();
  }

  void setRegionCode(String value) {
    if (regionCode.value == value) return;
    regionCode.value = value;
    codeController.clear();
    verificationRequestId.value = null;
    _stopCountdown();
  }

  Future<void> sendCode() async {
    if (isSendingCode.value || resendSeconds.value > 0) return;
    final account = accountController.text.trim();
    final error = _validateAccount(account);
    if (error != null) {
      AppToast.warning(error);
      return;
    }

    isSendingCode.value = true;
    try {
      final challenge = await _repository.requestPasswordResetCode(
        channel: mode.value.name,
        target: account,
        countryCode: mode.value == RegisterMode.phone
            ? RegionCodeOption.byCode(regionCode.value).dialCode
            : null,
      );
      verificationRequestId.value = challenge.requestId;
      if (challenge.developmentCode != null) {
        codeController.text = challenge.developmentCode!;
      }
      _startCountdown(challenge.resendIn);
      AppToast.success('验证码已发送至 ${challenge.targetMasked}');
    } on ApiException catch (error) {
      AppToast.error(error.message);
    } catch (_) {
      AppToast.error('验证码发送失败，请稍后重试');
    } finally {
      isSendingCode.value = false;
    }
  }

  Future<void> resetPassword() async {
    if (isSubmitting.value) return;
    final account = accountController.text.trim();
    final accountError = _validateAccount(account);
    if (accountError != null) {
      AppToast.warning(accountError);
      return;
    }
    final requestId = verificationRequestId.value;
    if (requestId == null) {
      AppToast.warning('请先获取验证码');
      return;
    }
    final code = codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      AppToast.warning('请输入 6 位验证码');
      return;
    }
    final password = passwordController.text;
    if (password.isEmpty) {
      AppToast.warning('请输入新密码');
      return;
    }
    if (password != confirmPasswordController.text) {
      AppToast.warning('两次输入的密码不一致');
      return;
    }

    isSubmitting.value = true;
    try {
      await _repository.resetPassword(
        channel: mode.value.name,
        account: account,
        countryCode: mode.value == RegisterMode.phone
            ? RegionCodeOption.byCode(regionCode.value).dialCode
            : null,
        verificationRequestId: requestId,
        code: code,
        newPassword: password,
      );
      AppToast.success('密码已重置，请使用新密码登录');
      Get.back();
    } on ApiException catch (error) {
      AppToast.error(error.message);
    } catch (_) {
      AppToast.error('密码重置失败，请稍后重试');
    } finally {
      isSubmitting.value = false;
    }
  }

  String? _validateAccount(String value) {
    if (value.isEmpty) return '请输入${mode.value.label}';
    if (mode.value == RegisterMode.email &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return '请输入有效邮箱';
    }
    if (mode.value == RegisterMode.phone &&
        !RegExp(r'^[+\d][\d\s-]{5,}$').hasMatch(value)) {
      return '请输入有效手机号';
    }
    return null;
  }

  void _startCountdown(int seconds) {
    _stopCountdown();
    resendSeconds.value = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (resendSeconds.value <= 1) {
        _stopCountdown();
      } else {
        resendSeconds.value--;
      }
    });
  }

  void _stopCountdown() {
    _timer?.cancel();
    _timer = null;
    resendSeconds.value = 0;
  }

  @override
  void onClose() {
    _timer?.cancel();
    accountController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}

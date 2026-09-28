/// 找回密码页面。
///
/// 沿用登录/注册页的紧凑认证表单，不改变既有视觉语言；验证码发送和重置
/// 均有按钮 Loading、禁用态及成功/失败 Toast。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/enums/register_mode.dart';
import '../../shared/widgets/region_code_picker.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import 'forgot_password_controller.dart';
import 'widgets/auth_brand_header.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

class ForgotPasswordPage extends GetView<ForgotPasswordController> {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      /*appBar: AppSearchAppBar(
        title: '',
        onBack: Get.back,
        backgroundColor: Colors.transparent,
        dividerColor: Colors.transparent,
      ),*/
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingXl,
              vertical: AppSizes.paddingLg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AuthBrandHeader(
                    title: '重置密码',
                    subtitle: '验证绑定的手机号或邮箱后设置新密码',
                    logo: false,
                  ),
                  const SizedBox(height: AppSizes.paddingXl),
                  _modeSwitch(context),
                  const SizedBox(height: AppSizes.paddingLg),
                  Obx(() {
                    final mode = controller.mode.value;
                    return AuthTextField(
                      label: mode.label,
                      hint: mode.hint,
                      icon: mode.icon,
                      controller: controller.accountController,
                      keyboardType: mode.keyboardType,
                      textInputAction: TextInputAction.next,
                      prefix:
                          mode == RegisterMode.phone
                              ? Obx(
                                () => RegionCodePickerButton(
                                  value: controller.regionCode.value,
                                  onChanged: controller.setRegionCode,
                                ),
                              )
                              : null,
                    );
                  }),
                  const SizedBox(height: AppSizes.paddingLg),
                  AuthTextField(
                    label: '验证码',
                    hint: '请输入 6 位验证码',
                    icon: Icons.verified_user_outlined,
                    controller: controller.codeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    suffix: _codeButton(context),
                  ),
                  const SizedBox(height: AppSizes.paddingLg),
                  AuthTextField(
                    label: '新密码',
                    hint: '请输入新密码',
                    icon: Icons.lock_outline,
                    obscure: true,
                    controller: controller.passwordController,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSizes.paddingLg),
                  AuthTextField(
                    label: '确认新密码',
                    hint: '请再次输入新密码',
                    icon: Icons.lock_reset_outlined,
                    obscure: true,
                    controller: controller.confirmPasswordController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => controller.resetPassword(),
                  ),
                  const SizedBox(height: AppSizes.paddingXl),
                  Obx(
                    () => AuthPrimaryButton(
                      label: '重置密码',
                      onPressed: controller.resetPassword,
                      loading: controller.isSubmitting.value,
                    ),
                  ),

                  const SizedBox(height: AppSizes.paddingLg),
                  _loginLink(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeSwitch(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.paddingXs),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
      ),
      child: Obx(() {
        final active = controller.mode.value;
        return Row(
          children: [
            for (final mode in RegisterMode.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.setMode(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSizes.paddingSm,
                    ),
                    decoration: BoxDecoration(
                      color:
                          mode == active
                              ? (context.isDark
                                  ? context.colorScheme.surface
                                  : Colors.white)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      mode.label,
                      style: AppTextStyles.messageBody.copyWith(
                        color:
                            mode == active
                                ? context.tokens.brand
                                : context.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _codeButton(BuildContext context) {
    return Obx(() {
      final sending = controller.isSendingCode.value;
      final seconds = controller.resendSeconds.value;
      return TextButton(
        onPressed: sending || seconds > 0 ? null : controller.sendCode,
        child: Text(
          sending
              ? '发送中'
              : seconds > 0
              ? '${seconds}s'
              : '获取验证码',
          style: AppTextStyles.metadata.copyWith(color: context.tokens.brand),
        ),
      );
    });
  }

  Widget _loginLink(BuildContext context) {
    final colors = context.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        /*Text(
          '已有账号?',
          style: AppTextStyles.metadata.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),*/
        GestureDetector(
          onTap: controller.goLogin,
          child: Text(
            '回去去登录',
            style: AppTextStyles.metadata.copyWith(
              color: context.tokens.brand,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

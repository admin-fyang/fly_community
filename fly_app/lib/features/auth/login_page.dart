/// 登录页。
///
/// 品牌头部 + 账号/密码输入 + 登录按钮 + 注册入口。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/services/system_time_service.dart';
import 'login_controller.dart';
import 'widgets/auth_brand_header.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_scale_scope.dart';
import 'widgets/auth_text_field.dart';

/// 登录页：收集账号密码并将提交事件交给 [LoginController]。
class LoginPage extends GetView<LoginController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return AuthTextScaleScope(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingXl,
                vertical: AppSizes.paddingXl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AuthBrandHeader(
                      title: '欢迎回来',
                      subtitle: '登录您的账号以继续',
                      logo: true,
                    ),
                    Obx(() {
                      final notice = controller.loginNotice.value;
                      return notice.isEmpty ? const SizedBox.shrink() : Padding(
                        padding: const EdgeInsets.only(top: AppSizes.paddingItem),
                        child: Text(notice, textAlign: TextAlign.center,
                          style: AppTextStyles.metadata.copyWith(
                            color: context.semanticColors.destructive,
                          )),
                      );
                    }),
                    const SizedBox(height: AppSizes.paddingXl),
                    AuthTextField(
                      label: '手机号 / 邮箱 / 用户名',
                      hint: '请输入手机号、邮箱或用户名',
                      icon: Icons.person_outline,
                      controller: controller.accountController,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSizes.paddingLg),
                    AuthTextField(
                      label: '密码',
                      hint: '请输入您的密码',
                      icon: Icons.lock_outline,
                      obscure: true,
                      controller: controller.passwordController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => controller.login(),
                      trailingLabel: '忘记密码?',
                      onTrailingLabelTap: controller.forgotPassword,
                    ),
                    const SizedBox(height: AppSizes.paddingXl),
                    Obx(
                      () => AuthPrimaryButton(
                        label: '登录',
                        onPressed: controller.login,
                        loading: controller.isSubmitting.value,
                      ),
                    ),
                    Obx(() {
                      final config = Get.find<SystemTimeService>();
                      config.revision.value;
                      if (!config.canRegister) return const SizedBox.shrink();
                      return Column(
                        children: [
                          const SizedBox(height: AppSizes.paddingXl),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '还没有账号？',
                                style: AppTextStyles.metadata.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              GestureDetector(
                                onTap: controller.goRegister,
                                child: Text(
                                  '立即注册',
                                  style: AppTextStyles.metadata.copyWith(
                                    color: context.tokens.brand,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

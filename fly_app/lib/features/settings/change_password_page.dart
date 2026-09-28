/// 修改密码页面。
///
/// 使用设置页统一外壳和认证输入组件，保持浅色/深色主题及紧凑间距一致。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../auth/widgets/auth_primary_button.dart';
import '../auth/widgets/auth_text_field.dart';
import 'change_password_controller.dart';
import 'widgets/settings_scaffold.dart';

class ChangePasswordPage extends GetView<ChangePasswordController> {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '修改密码',
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text(
          '修改成功后当前设备保持登录，其他设备会话将被撤销。',
          style: AppTextStyles.metadata.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSizes.paddingXl),
        AuthTextField(
          label: '当前密码',
          hint: '请输入当前密码',
          icon: Icons.lock_open_outlined,
          obscure: true,
          controller: controller.currentPasswordController,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSizes.paddingLg),
        AuthTextField(
          label: '新密码',
          hint: '请输入新密码',
          icon: Icons.lock_outline,
          obscure: true,
          controller: controller.newPasswordController,
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
          onSubmitted: (_) => controller.submit(),
        ),
        const SizedBox(height: AppSizes.paddingXl),
        Obx(
          () => AuthPrimaryButton(
            label: '确认修改',
            onPressed: controller.submit,
            loading: controller.isSubmitting.value,
          ),
        ),
      ],
    );
  }
}

/// 申请注销账号页面。
///
/// 危险操作使用错误色并二次确认；提交期间按钮显示旋转 Loading 且禁止重复点击。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../auth/widgets/auth_text_field.dart';
import 'delete_account_controller.dart';
import 'widgets/settings_scaffold.dart';

class DeleteAccountPage extends GetView<DeleteAccountController> {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '注销账号',
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSizes.paddingLg),
          decoration: BoxDecoration(
            color: context.tokens.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
            border: Border.all(
              color: context.tokens.danger.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: context.tokens.danger,
                size: 22,
              ),
              const SizedBox(width: AppSizes.paddingMd),
              Expanded(
                child: Text(
                  '提交后账号进入 30 天冷静期。冷静期内可从账号安全页取消；到期后账号将被注销。',
                  style: AppTextStyles.metadata.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.paddingXl),
        AuthTextField(
          label: '当前密码',
          hint: '输入当前密码确认本人操作',
          icon: Icons.lock_outline,
          obscure: true,
          controller: controller.passwordController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => controller.submit(),
        ),
        const SizedBox(height: AppSizes.paddingXl),
        SizedBox(
          height: 48,
          child: Obx(
            () => FilledButton(
              onPressed: controller.isSubmitting.value
                  ? null
                  : controller.submit,
              style: FilledButton.styleFrom(
                backgroundColor: context.tokens.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
                ),
              ),
              child: controller.isSubmitting.value
                  ? const SizedBox.square(
                      dimension: 20,
                      child: AppLoadingIndicator(
                        size: 20,
                        color: Colors.white,
                      ),
                    )
                  : const Text('申请注销账号'),
            ),
          ),
        ),
      ],
    );
  }
}

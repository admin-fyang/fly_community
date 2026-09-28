/// 账号(安全)页。
///
/// 基本信息展示 + 修改密码 / 注销账号等账户安全操作。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../shared/widgets/section_card.dart';
import 'account_security_controller.dart';
import 'widgets/settings_scaffold.dart';
import 'widgets/settings_tile.dart';

/// 账号(安全):基本信息展示 + 账户安全操作
class AccountSettingsPage extends GetView<AccountSecurityController> {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SettingsScaffold(
      readActivity: controller.pageReads,
      title: '账号',
      actions: [
        // IconButton(
        //   icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
        //   onPressed: () {},
        // ),
      ],
      children: [
        const SettingsSectionHeader('账户安全'),
        Obx(
          () => SectionCard(
            children: [
              SettingsTile(
                icon: Icons.lock_open,
                iconColor: colors.onSurfaceVariant,
                title: '修改密码',
                onTap: controller.openChangePassword,
              ),
              SettingsTile(
                icon: Icons.delete_forever,
                iconColor: context.tokens.danger,
                title: '注销账号',
                danger: true,
                onTap: controller.openDeleteAccount,
              ),
              if (controller.isCheckingDeletion.value)
                const SettingsTile(
                  icon: Icons.hourglass_top_rounded,
                  title: '正在检查注销状态',
                  trailing: SizedBox.square(
                    dimension: 18,
                    child: AppLoadingIndicator(size: 18),
                  ),
                ),
              if (controller.hasPendingDeletion.value)
                SettingsTile(
                  icon: Icons.restore,
                  iconColor: context.tokens.brand,
                  title: '取消注销申请',
                  subtitle: controller.isCancellingDeletion.value
                      ? '正在取消...'
                      : '仅在 30 天冷静期内可操作',
                  onTap: controller.isCancellingDeletion.value
                      ? null
                      : controller.cancelDeletion,
                ),
            ],
          ),
        ),
        /*const SizedBox(height: AppSizes.paddingXl),
        Center(
          child: Text(
            'App 版本 10.4.2 (4192) Arm64-v8a',
            style: AppTextStyles.metadata.copyWith(
              color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),*/
      ],
    );
  }
}

/// 设置主页。
///
/// 抽屉「设置」入口,分组罗列各设置项,底部退出登录。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_controller.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/interaction/app_pressable.dart';
import '../../shared/widgets/section_card.dart';
import 'settings_controller.dart';
import 'widgets/settings_scaffold.dart';
import 'widgets/settings_tile.dart';

/// 设置主页 SVG 图标资源。
///
/// 集中维护路径，避免页面条目散落资源字符串；图标本身包含完整背景与配色，
/// 深浅色主题下均按原始设计展示。
abstract final class _SettingsIconAssets {
  static const String myProfile = 'assets/icons/settings/my_profile.svg';
  static const String accountSecurity =
      'assets/icons/settings/account_security.svg';
  static const String notificationsSound =
      'assets/icons/settings/notifications_sound.svg';
  static const String chatSettings = 'assets/icons/settings/chat_settings.svg';
  static const String themeSettings =
      'assets/icons/settings/theme_settings.svg';
  static const String dataStorage = 'assets/icons/settings/data_storage.svg';
  static const String privacySecurity =
      'assets/icons/settings/privacy_security.svg';
  static const String faq = 'assets/icons/settings/faq.svg';
  static const String privacyPolicy =
      'assets/icons/settings/privacy_policy.svg';
  static const String checkUpdate = 'assets/icons/settings/check_update.svg';
}

/// 设置主页(抽屉「设置」入口)
///
/// 分组罗列各设置入口，未开放的后端能力提供明确反馈。
class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.semanticColors;

    return SettingsScaffold(
      title: '设置',
      actions: [
        _SettingsAppBarAction(
          // 搜索按钮只消费全局语义色，随明暗主题自动切换。
          color: context.isDark ? palette.textPrimary : palette.textSecondary,
          pressedColor: palette.surfacePressed,
          onTap: () => AppToast.info('设置搜索将在后续版本提供'),
        ),
      ],
      children: [
        SectionCard(
          dividerIndent: AppSizes.settingsTextInset,
          children: [
            _tile(
              palette,
              iconAsset: _SettingsIconAssets.chatSettings,
              title: '聊天设置',
              subtitle: '文本大小、背景、聊天列表',
              onTap: () => Get.toNamed(AppRoutes.chatSettings),
            ),
            Obx(() {
              final mode = Get.find<ThemeController>().mode;
              return _tile(
                palette,
                iconAsset: _SettingsIconAssets.themeSettings,
                title: '主题设置',
                subtitle: '浅色、深色或跟随系统',
                valueText: mode.settingsLabel,
                onTap: () => Get.toNamed(AppRoutes.themeSettings),
              );
            }),
            _tile(
              palette,
              iconAsset: _SettingsIconAssets.dataStorage,
              title: '数据和存储',
              subtitle: '清理本地图片缓存',
              onTap: () => Get.toNamed(AppRoutes.dataSettings),
            ),
            _tile(
              palette,
              icon: Icons.devices_outlined,
              iconColor: palette.accent,
              title: '设备管理',
              subtitle: '查看登录设备、退出其他登录会话',
              onTap: () => Get.toNamed(AppRoutes.deviceManagement),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sectionGap),
        // 关于
        SectionCard(
          children: [
            _tile(
              palette,
              iconAsset: _SettingsIconAssets.privacyPolicy,
              title: '隐私政策',
              subtitle: '了解我们如何保护您的隐私',
              onTap: controller.openPrivacyPolicy,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.paddingXl),
        _logoutButton(context, palette),
      ],
    );
  }

  Widget _tile(
    AppSemanticColors palette, {
    String? iconAsset,
    IconData? icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    String? valueText,
    required VoidCallback onTap,
  }) {
    return SettingsTile(
      iconAsset: iconAsset,
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      valueText: valueText,
      pressedColor: palette.surfacePressed,
      titleColor: palette.textPrimary,
      subtitleColor: palette.textSecondary,
      valueColor: palette.textSecondary,
      chevronColor: palette.textTertiary,
      useTelegramMetrics: true,
      onTap: onTap,
    );
  }

  Widget _logoutButton(BuildContext context, AppSemanticColors palette) {
    return SizedBox(
      height: 52,
      child: Obx(
        () => AppPressable(
          semanticLabel: '退出登录',
          onTap: controller.isLoggingOut.value
              ? null
              : () => _confirmLogout(context),
          normalColor: palette.surface,
          pressedColor: palette.surfacePressed,
          borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
          child: Center(
            child: Text(
              controller.isLoggingOut.value ? '正在退出...' : '退出登录',
              style: AppTextStyles.buttonLabel.copyWith(
                color: controller.isLoggingOut.value
                    ? palette.textSecondary
                    : palette.destructive,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await AppConfirmDialog.show(
      title: '退出登录',
      message: '确定要退出当前账号吗?',
      confirmText: '退出',
      danger: true,
    );
    if (ok == true) {
      await controller.logout();
    }
  }
}

class _SettingsAppBarAction extends StatelessWidget {
  const _SettingsAppBarAction({
    required this.color,
    required this.pressedColor,
    required this.onTap,
  });

  final Color color;
  final Color pressedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: SizedBox(
        width: 44,
        height: 44,
        child: AppPressable(
          semanticLabel: '搜索设置',
          onTap: onTap,
          pressedColor: pressedColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          child: Center(
            child: Icon(Icons.search_rounded, size: 21, color: color),
          ),
        ),
      ),
    );
  }
}

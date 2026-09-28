/// “我的”一级页面。
///
/// 一级页只承担账号识别和功能分发；完整资料放在编辑页，避免把联系人详情页
/// 的信息陈列结构搬到主导航中。
library;

import 'package:flychat/shared/widgets/search/app_search_app_bar.dart';
import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../main_navigation/main_navigation_insets.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/profile_detail_model.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/interaction/app_pressable.dart';
import '../../shared/widgets/loading/app_refresh_indicator.dart';
import '../../shared/widgets/section_card.dart';
import '../profile/widgets/profile_hero.dart';
import '../settings/widgets/settings_tile.dart';
import 'mine_controller.dart';

class MinePage extends GetView<MineController> {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      readActivity: controller.pageReads,
      appBar: AppSearchAppBar(
        title: '我的',
        showLeading: false,
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: controller.openSettings,
            icon: Icon(Icons.settings_outlined, color: semantic.textSecondary),
          ),
        ],
      ),
      backgroundColor: semantic.backgroundGrouped,
      body: Obx(() {
        final detail = controller.heroDetail;
        return AppRefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: (EdgeInsets.fromLTRB(
              AppSizes.paddingLg,
              0,
              AppSizes.paddingLg,
              AppSizes.paddingXl + MainNavigationInsets.bottomOf(context),
            )).add(EdgeInsets.only(top: appTopBarInset(context))),
            children: [
              _accountCard(context, detail),
              if (controller.errorMessage.value.isNotEmpty) ...[
                const SizedBox(height: AppSizes.paddingSm),
                _loadError(context),
              ],

              SectionCard(
                dividerIndent: AppSizes.settingsTextInset,
                children: [
                  _menuTile(
                    context,
                    icon: null,
                    iconAsset: 'assets/icons/settings/my_profile.svg',
                    title: '我的资料',
                    subtitle: '编辑头像、昵称与个人介绍',
                    onTap: controller.openEditProfile,
                  ),
                  _menuTile(
                    context,
                    icon: null,
                    iconAsset: 'assets/icons/settings/account_security.svg',
                    title: '账号安全',
                    subtitle: '密保、两步验证、注销账号',
                    onTap: () => Get.toNamed(AppRoutes.accountSettings),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sectionGap),
            ],
          ),
        );
      }),
    );
  }

  Widget _accountCard(BuildContext context, ProfileDetailModel detail) {
    final semantic = context.semanticColors;
    return AppPressable(
      key: const ValueKey('mine-account-card'),
      semanticLabel: '查看和编辑个人资料',
      onTap: controller.openEditProfile,
      pressedColor: semantic.surfacePressed,
      borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
      child: ProfileHero(detail: detail),
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData? icon,
    required String? iconAsset,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final semantic = context.semanticColors;
    return SettingsTile(
      icon: icon,
      iconAsset: iconAsset,
      title: title,
      subtitle: subtitle,
      pressedColor: semantic.surfacePressed,
      titleColor: semantic.textPrimary,
      subtitleColor: semantic.textSecondary,
      chevronColor: semantic.textTertiary,
      useTelegramMetrics: true,
      onTap: onTap,
    );
  }

  Widget _loadError(BuildContext context) {
    final semantic = context.semanticColors;
    return AppPressable(
      semanticLabel: '重试加载个人资料',
      onTap: controller.load,
      normalColor: semantic.surface,
      pressedColor: semantic.surfacePressed,
      borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingLg,
          vertical: AppSizes.paddingItem,
        ),
        child: Row(
          children: [
            Icon(Icons.refresh_rounded, color: semantic.accent, size: 19),
            const SizedBox(width: AppSizes.paddingSm),
            Expanded(
              child: Text(
                controller.errorMessage.value,
                style: AppTextStyles.metadata.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

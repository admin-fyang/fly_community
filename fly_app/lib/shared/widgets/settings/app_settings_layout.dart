/// 应用普通设置页面的统一视觉骨架。
///
/// V4 将设置类子页面统一成更接近 Telegram-iOS 的 grouped surface：
/// 低对比分组画布、轻量 section label、连续表面、1 physical pixel 分隔线。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../interaction/app_pressable.dart';
import '../search/app_search_app_bar.dart';

class AppSettingsPageScaffold extends StatelessWidget {
  const AppSettingsPageScaffold({
    super.key,
    required this.title,
    this.isReading,
    this.readActivity,
    required this.children,
    this.bottom,
  });

  final String title;

  /// 只读取当前页面的异步查询状态，不包含保存按钮等写入任务。
  final bool Function()? isReading;
  final PageReadActivity? readActivity;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return AppPageScaffold(
      topContentGap: AppSizes.paddingItem,
      isReading: isReading,
      readActivity: readActivity,
      extendBodyBehindAppBar: true,
      backgroundColor: semantic.backgroundGrouped,
      appBar: AppSearchAppBar(
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
        // Telegram-iOS Night keeps navigation material separate from the
        // true-black grouped canvas: #1D1D1D @ 90% with #545458 @ 55% hairline.
        backgroundColor: context.isDark
            ? AppColors.darkHomeAppBar
            : semantic.backgroundGrouped,
        foregroundColor: semantic.textPrimary,
        dividerColor: context.isDark
            ? AppColors.darkHomeAppBarDivider
            : Colors.transparent,
      ),
      body: ListView(
        padding: (EdgeInsets.only(
          top: AppSizes.paddingItem,
          bottom: bottom == null ? AppSizes.paddingXl : 104,
        )).add(EdgeInsets.only(top: appTopBarInset(context))),
        children: children,
      ),
      bottomNavigationBar: bottom == null
          ? null
          : Builder(
              builder: (context) {
                final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: semantic.surface,
                    border: Border(
                      top: BorderSide(
                        color: semantic.separator,
                        width: 1 / MediaQuery.devicePixelRatioOf(context),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.paddingLg,
                      AppSizes.paddingItem,
                      AppSizes.paddingLg,
                      AppSizes.paddingItem + systemBottom,
                    ),
                    child: bottom!,
                  ),
                );
              },
            ),
    );
  }
}

class AppSettingsSection extends StatelessWidget {
  const AppSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final List<Widget> children;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.paddingLg,
        AppSizes.paddingXs,
        AppSizes.paddingLg,
        AppSizes.paddingItem,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.paddingItem,
              0,
              AppSizes.paddingItem,
              6,
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Text(
                title,
                style: AppTextStyles.metadata.copyWith(
                  color: semantic.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: semantic.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
              child: Column(
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    children[index],
                    if (index != children.length - 1)
                      _SettingsHairline(color: semantic.separator, indent: 56),
                  ],
                ],
              ),
            ),
          ),
          if (description?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.paddingItem,
                7,
                AppSizes.paddingItem,
                0,
              ),
              child: Text(
                description!,
                style: AppTextStyles.metadata.copyWith(
                  color: semantic.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppSettingsTile extends StatelessWidget {
  const AppSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final hasSubtitle = subtitle?.trim().isNotEmpty == true;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: AppPressable(
        semanticLabel: title,
        onTap: onTap,
        pressedColor: semantic.surfacePressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: hasSubtitle ? 60 : 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingItem,
              vertical: AppSizes.paddingSm,
            ),
            child: Row(
              children: [
                /*Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: semantic.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  // child: Icon(icon, size: 18, color: semantic.accent),
                  child: SvgPicture.asset(
                    icon,
                    width: 19,
                    height: 19,
                    colorFilter: ColorFilter.mode(semantic.accent, BlendMode.srcIn),
                  ),
                ),*/

                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    icon,
                    width: 19,
                    height: 19,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: AppSizes.paddingItem),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.listPrimary.copyWith(
                          color: semantic.textPrimary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.metadata.copyWith(
                            color: semantic.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSizes.paddingItem),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsHairline extends StatelessWidget {
  const _SettingsHairline({required this.color, required this.indent});

  final Color color;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: SizedBox(
        height: 1 / MediaQuery.devicePixelRatioOf(context),
        child: ColoredBox(color: color),
      ),
    );
  }
}

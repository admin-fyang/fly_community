/// Settings row and section header primitives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/interaction/app_pressable.dart';

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.paddingSm,
        AppSizes.paddingLg,
        AppSizes.paddingSm,
        AppSizes.paddingSm,
      ),
      child: Text(
        label,
        style: AppTextStyles.metadata.copyWith(
          color: context.semanticColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    this.icon,
    this.iconAsset,
    this.iconColor,
    this.title,
    this.subtitle,
    this.valueText,
    this.trailing,
    this.showChevron = true,
    this.danger = false,
    this.onTap,
    this.pressedColor,
    this.titleColor,
    this.subtitleColor,
    this.valueColor,
    this.chevronColor,
    this.useTelegramMetrics = false,
  }) : assert(icon == null || iconAsset == null, 'icon 与 iconAsset 不能同时设置');

  final IconData? icon;
  final String? iconAsset;
  final Color? iconColor;
  final String? title;
  final String? subtitle;
  final String? valueText;
  final Widget? trailing;
  final bool showChevron;
  final bool danger;
  final VoidCallback? onTap;

  /// Optional presentation overrides used by a screen that needs to mirror a
  /// specific Telegram list palette without changing every settings screen.
  final Color? pressedColor;
  final Color? titleColor;
  final Color? subtitleColor;
  final Color? valueColor;
  final Color? chevronColor;
  final bool useTelegramMetrics;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final effectiveTitleColor =
        titleColor ?? (danger ? semantic.destructive : semantic.textPrimary);
    final effectiveSubtitleColor = subtitleColor ?? semantic.textSecondary;
    final hasSubtitle = subtitle?.trim().isNotEmpty == true;
    final titleFontSize = useTelegramMetrics ? 17.0 : 15.5;
    final titleLineHeight = useTelegramMetrics ? 22.0 : 21.0;
    final subtitleFontSize = useTelegramMetrics ? 15.0 : 13.5;
    final subtitleLineHeight = useTelegramMetrics ? 19.0 : 18.0;
    final verticalPadding = useTelegramMetrics ? 11.0 : 10.0;
    final titleSubtitleGap = useTelegramMetrics ? 1.0 : 2.0;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: AppPressable(
        semanticLabel: title,
        onTap: onTap,
        pressedColor: pressedColor ?? semantic.surfacePressed,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.paddingLg,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              if (icon != null || iconAsset != null) ...[
                _leadingIcon(context),
                const SizedBox(width: AppSizes.paddingItem),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        strutStyle: StrutStyle(
                          fontSize: titleFontSize,
                          height: titleLineHeight / titleFontSize,
                          forceStrutHeight: true,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.listPrimary.copyWith(
                          color: effectiveTitleColor,
                          fontSize: titleFontSize,
                          height: titleLineHeight / titleFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    if (hasSubtitle) ...[
                      SizedBox(height: titleSubtitleGap),
                      Text(
                        subtitle!,
                        strutStyle: StrutStyle(
                          fontSize: subtitleFontSize,
                          height: subtitleLineHeight / subtitleFontSize,
                          forceStrutHeight: true,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.settingsSubtitle.copyWith(
                          color: effectiveSubtitleColor,
                          fontSize: subtitleFontSize,
                          height: subtitleLineHeight / subtitleFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _trailing(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leadingIcon(BuildContext context) {
    if (iconAsset != null) {
      return SvgPicture.asset(
        iconAsset!,
        width: 30,
        height: 30,
        excludeFromSemantics: true,
      );
    }

    final semantic = context.semanticColors;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: (iconColor ?? semantic.accent).withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor ?? semantic.accent, size: 18),
    );
  }

  Widget _trailing(BuildContext context) {
    if (trailing != null) return trailing!;
    final semantic = context.semanticColors;
    final chevron = showChevron
        ? Icon(
            Icons.arrow_forward_ios_rounded,
            size: 12,
            color: chevronColor ?? semantic.textTertiary,
          )
        : const SizedBox.shrink();
    if (valueText == null) return chevron;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valueText!,
          style: AppTextStyles.metadata.copyWith(
            color: valueColor ?? semantic.accent,
            fontSize: useTelegramMetrics ? 15.0 : null,
            height: useTelegramMetrics ? 19 / 15 : null,
            fontWeight: useTelegramMetrics ? FontWeight.w400 : FontWeight.w500,
          ),
        ),
        const SizedBox(width: AppSizes.paddingXs),
        chevron,
      ],
    );
  }
}

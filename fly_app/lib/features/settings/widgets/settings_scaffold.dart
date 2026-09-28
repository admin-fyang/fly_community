/// Shared shell for grouped settings screens.
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/search/app_search_app_bar.dart';

/// Telegram-iOS-inspired grouped settings shell:
/// a low-contrast canvas + clean navigation surface + grouped item surfaces.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    this.isReading,
    this.readActivity,
    required this.children,
    this.actions,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.appBarIconColor,
    this.titleStyle,
    this.showAppBarDivider = false,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: AppSizes.paddingLg,
      vertical: AppSizes.paddingItem,
    ),
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final String title;

  /// 只读取当前页面的异步查询状态，不包含保存按钮等写入任务。
  final bool Function()? isReading;
  final PageReadActivity? readActivity;
  final List<Widget> children;
  final List<Widget>? actions;

  /// Optional page-level grouped background override.
  ///
  /// Kept additive so existing settings screens preserve their current theme.
  final Color? backgroundColor;
  final Color? appBarBackgroundColor;
  final Color? appBarIconColor;
  final TextStyle? titleStyle;
  final bool showAppBarDivider;
  final EdgeInsetsGeometry contentPadding;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final groupedBackground = backgroundColor ?? semantic.backgroundGrouped;
    return AppPageScaffold(
      topContentGap: contentPadding.resolve(Directionality.of(context)).top,
      isReading: isReading,
      readActivity: readActivity,
      extendBodyBehindAppBar: true,
      backgroundColor: groupedBackground,
      appBar: AppSearchAppBar(
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
        backgroundColor:
            appBarBackgroundColor ??
            (context.isDark ? AppColors.darkHomeAppBar : groupedBackground),
        foregroundColor: appBarIconColor ?? semantic.textPrimary,
        titleStyle:
            titleStyle ??
            AppTextStyles.pageTitleMobile.copyWith(
              color: semantic.textPrimary,
              fontWeight: FontWeight.w500,
            ),
        actions: actions ?? const [],
        dividerColor: showAppBarDivider
            ? semantic.separator
            : Colors.transparent,
      ),
      body: ListView(
        keyboardDismissBehavior: keyboardDismissBehavior,
        padding: (contentPadding).add(
          EdgeInsets.only(top: appTopBarInset(context)),
        ),
        children: children,
      ),
    );
  }
}

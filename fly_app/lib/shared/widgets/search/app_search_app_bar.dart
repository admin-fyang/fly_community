/// 通用「普通 ↔ 搜索」顶栏组件。
///
/// 统一首页及各级页面的图标、标题和操作区几何；传入完整搜索配置时，点击搜索
/// 图标以 AnimatedSwitcher 平滑切到搜索框并聚焦，省略搜索配置时只展示标题栏。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/enums/top_bar_mode.dart';
import '../navigation/app_navigation_button.dart';
import '../navigation/app_top_bar.dart';
import 'app_search_field.dart';

/// 通用「普通 ↔ 搜索」顶栏
///
/// 首页、聊天、资料、设置和业务页面共用。左侧支持抽屉、返回或关闭图标；标题
/// 区支持普通文字及自定义内容；搜索能力必须成组配置，避免无搜索页面出现空入口。
class AppSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSearchAppBar({
    super.key,
    required this.title,
    this.mode,
    this.onOpenSearch,
    this.onCloseSearch,
    this.onChanged,
    this.showDrawerButton = false,
    this.showLeading = true,
    this.onBack,
    this.bottom,
    this.searchController,
    this.searchOnly = false,
    this.searchHint = '搜索...',
    this.actions = const [],
    this.actionsBeforeSearch = false,
    this.titleWidget,
    this.titleLeading,
    this.titleStyle,
    this.leadingIcon = Icons.arrow_back_rounded,
    this.leadingTooltip,
    this.iconSize,
    this.foregroundColor,
    this.backgroundColor,
    this.dividerColor,
  }) : assert(
         (searchOnly &&
                 mode == null &&
                 onChanged != null &&
                 onCloseSearch != null) ||
             (mode == null &&
                 onOpenSearch == null &&
                 onCloseSearch == null &&
                 onChanged == null) ||
             (mode != null &&
                 onOpenSearch != null &&
                 onCloseSearch != null &&
                 onChanged != null),
         '搜索状态与三个搜索回调必须同时提供或同时省略',
       );

  final String title;

  /// 原页面的固定搜索、筛选等交互迁入公共顶栏的附加区，保持原有高度。
  final PreferredSizeWidget? bottom;

  /// 搜索状态及回调必须同时提供；全部省略时组件仅渲染返回、标题和右侧动作。
  final Rx<TopBarMode>? mode;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onCloseSearch;
  final ValueChanged<String>? onChanged;

  /// 左侧用抽屉按钮（true）还是返回按钮（false）
  final bool showDrawerButton;

  /// 根级底部页签不展示返回按钮；普通二级页面保持默认值。
  final bool showLeading;
  final VoidCallback? onBack;
  final String searchHint;

  /// 专用搜索页面直接进入输入模式，仍共用输入、清除、聚焦和返回交互。
  final bool searchOnly;

  /// 调用方持有输入状态，返回页面后不丢失关键词与选择范围。
  final TextEditingController? searchController;
  final List<Widget> actions;

  /// 需要保留“搜索”为最右侧主操作的顶栏，可将辅助动作放在其前。
  final bool actionsBeforeSearch;

  /// 动态标题、头像标题或吸附 Tab 等复杂标题内容；提供后覆盖 [title] 的渲染。
  final Widget? titleWidget;
  final Widget? titleLeading;
  final TextStyle? titleStyle;
  final IconData leadingIcon;

  /// 左侧导航按钮的语义提示；特殊动作（如“最小化通话”）必须显式传入，
  /// 避免读屏仍把它误报为普通返回操作。
  final String? leadingTooltip;
  final double? iconSize;
  final Color? foregroundColor;
  /// 兼容旧页面参数；背景和分割线统一由 AppTopBar 管理，不再逐页覆盖。
  /// 新页面应在 AppPageScaffold 设置页面底色，由公共顶栏自动取色。
  final Color? backgroundColor;
  final Color? dividerColor;

  @override
  Size get preferredSize => Size.fromHeight(
    AppSizes.appBarHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final content = searchOnly
        ? _searchBar(context)
        : mode == null
        ? _normalBar(context, colors)
        : Obx(() {
            final isSearch = mode!.value == TopBarMode.search;
            return AnimatedSwitcher(
              duration: AppConstants.animNormal,
              reverseDuration: AppConstants.animFast,
              switchInCurve: AppConstants.motionStandard,
              switchOutCurve: AppConstants.motionExit,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: isSearch
                  ? _searchBar(context)
                  : _normalBar(context, colors),
            );
          });

    return AppTopBar(
      foregroundColor: foregroundColor,
      height: preferredSize.height,
      padding: EdgeInsets.zero,
      showStatus: false,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: 1,
        maxScaleFactor: 1,
        child: Column(
          children: [
            SizedBox(
              height: AppSizes.appBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.paddingSm,
                ),
                child: Row(
                  children: [
                    Expanded(child: content),
                    // 普通页面的加载色统一使用主题 accent，不能继承标题/操作图标色。
                    // 通话和媒体等沉浸式页面由 AppTopBarStatus 显式配置白色。
                    const AppTopBarStatus(),
                  ],
                ),
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }

  Widget _normalBar(BuildContext context, ColorScheme colors) {
    return Row(
      key: const ValueKey('normal'),
      children: [
        if (showDrawerButton)
          Builder(
            builder: (ctx) => AppNavigationButton(
              icon: Icons.menu_rounded,
              tooltip: leadingTooltip,
              iconSize: iconSize ?? 21,
              color: foregroundColor ?? colors.onSurface,
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          )
        else if (showLeading)
          AppNavigationButton(
            icon: leadingIcon,
            tooltip: leadingTooltip,
            iconSize: iconSize ?? 21,
            color: foregroundColor ?? colors.onSurface,
            onPressed: onBack,
          ),
        if (titleLeading != null) ...[
          const SizedBox(width: 6),
          titleLeading!,
          const SizedBox(width: AppSizes.paddingMd),
        ],
        Expanded(
          child:
              titleWidget ??
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    titleStyle ??
                    AppTextStyles.navTitleMobile.copyWith(
                      color: colors.onSurface,
                    ),
              ),
        ),
        if (actionsBeforeSearch) _actions(context, colors),
        if (mode != null)
          AppNavigationButton(
            icon: Icons.search_rounded,
            iconSize: iconSize ?? 21,
            color: foregroundColor ?? colors.onSurface,
            onPressed: onOpenSearch,
          ),
        if (!actionsBeforeSearch) _actions(context, colors),
      ],
    );
  }

  Widget _actions(BuildContext context, ColorScheme colors) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.square(40)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          iconSize: WidgetStatePropertyAll(iconSize ?? 21),
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return context.semanticColors.surfacePressed.withValues(
                alpha: 0.68,
              );
            }
            return Colors.transparent;
          }),
        ),
      ),
      child: IconTheme.merge(
        data: IconThemeData(
          color: foregroundColor ?? colors.onSurface,
          size: iconSize ?? 21,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('search'),
      child: AppSearchField(
        controller: searchController,
        onBack: onCloseSearch!,
        onChanged: onChanged!,
        hint: searchHint,
      ),
    );
  }
}

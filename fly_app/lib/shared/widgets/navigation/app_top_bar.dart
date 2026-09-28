/// 全局顶部栏：透明/磨砂表面、页面读取反馈以及独立的网络恢复入口。
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../loading/app_loading_indicator.dart';
import '../network/network_connection_indicator.dart';

/// 每个页面单独持有的展示状态，不进入全局 Get 注册表，不会串到其它页面。
///
/// 滚动通知和刷新手势只更新这里的展示状态；Widget 不处理网络或业务数据。
class AppTopBarController extends GetxController {
  final overlapsContent = false.obs;
  final refreshStatus = Rxn<RefreshIndicatorStatus>();
  bool _disposed = false;
  Object? _refreshOwner;

  void setOverlap(bool value) {
    if (!_disposed && overlapsContent.value != value) {
      overlapsContent.value = value;
    }
  }

  void setRefreshStatus(RefreshIndicatorStatus? value, {Object? owner}) {
    final ending =
        value == null ||
        value == RefreshIndicatorStatus.done ||
        value == RefreshIndicatorStatus.canceled;
    if (ending && owner != null && owner != _refreshOwner) return;
    if (value != null) _refreshOwner = owner;
    if (!_disposed && refreshStatus.value != value) refreshStatus.value = value;
  }

  @override
  void onClose() {
    _disposed = true;
    super.onClose();
  }
}

/// 顶栏及页面正文共享的局部作用域；读取回调在 Obx 内执行，以订阅业务 Rx。
class AppTopBarScope extends InheritedWidget {
  const AppTopBarScope({
    super.key,
    required this.controller,
    required super.child,
    this.isReading,
    this.topInset = 0,
  });

  final AppTopBarController controller;
  final bool Function()? isReading;
  final double topInset;

  static AppTopBarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTopBarScope>();

  @override
  bool updateShouldNotify(AppTopBarScope oldWidget) =>
      controller != oldWidget.controller ||
      isReading != oldWidget.isReading ||
      topInset != oldWidget.topInset;
}

/// 当前设备上普通顶栏与状态栏所占的总高度。
///
/// 滚动页面将该高度加入列表内部的物理顶部 padding，不能用外层 Padding
/// 缩小视口，否则内容永远无法滚到顶栏背后，BackdropFilter 也无法产生磨砂。
double appTopBarInset(BuildContext context, {double? height}) =>
    height == null && AppTopBarScope.maybeOf(context) != null
    ? AppTopBarScope.maybeOf(context)!.topInset
    : MediaQuery.viewPaddingOf(context).top + (height ?? AppSizes.appBarHeight);

/// 顶栏共同的视觉外壳。自定义内容保留原有高度、头像、标题和操作布局。
///
/// 背景模糊只绘制在裁剪后的顶栏区域；透明状态不创建模糊层。动画只改变
/// 表面透明度，始终保持顶栏尺寸不变。沉浸式页面可指定白色前景及深色底色。
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.child,
    this.height = AppSizes.appBarHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSizes.paddingSm),
    this.foregroundColor,
    this.darkSurface = false,
    this.safeArea = true,
    this.showStatus = true,
    this.isReading,
  });

  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  final Color? foregroundColor;
  final bool darkSurface;
  final bool safeArea;
  final bool showStatus;
  final bool Function()? isReading;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final scope = AppTopBarScope.maybeOf(context);
    final dark = darkSurface || context.isDark;
    final foreground =
        foregroundColor ??
        (darkSurface ? Colors.white : context.semanticColors.textPrimary);
    final surface =
        (dark
                ? AppColors.darkHomeAppBar
                : context.semanticColors.backgroundPrimary)
            .withValues(alpha: dark ? .78 : .72);
    final content = SizedBox(
      height: height,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: child),
            if (showStatus)
              AppTopBarStatus(color: foreground, isReading: isReading),
          ],
        ),
      ),
    );
    final background =
        Scaffold.maybeOf(context)?.widget.backgroundColor ??
        Theme.of(context).scaffoldBackgroundColor;
    final iconBrightness =
        darkSurface ||
            ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: iconBrightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
      ),
      child: ClipRect(
        child: Stack(
          children: [
            if (scope != null)
              Positioned.fill(
                child: Obx(
                  () => TweenAnimationBuilder<double>(
                    tween: Tween(
                      end: scope.controller.overlapsContent.value ? 1.0 : 0.0,
                    ),
                    duration: const Duration(milliseconds: 180),
                    builder: (context, opacity, _) => opacity <= 0
                        ? const SizedBox.shrink()
                        : Opacity(
                            opacity: opacity,
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: ColoredBox(color: surface),
                            ),
                          ),
                  ),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: safeArea
                  ? SafeArea(bottom: false, child: content)
                  : content,
            ),
          ],
        ),
      ),
    );
  }
}

/// 独立并列的两个状态位：页面读取在左，网络异常/恢复在右。
///
/// 读取指示器没有点击动作；网络标识保留原有重试事件。空闲时不占宽度，
/// 出现时只淡入图标，不对标题宽度或栏高执行补间动画。
class AppTopBarStatus extends StatelessWidget {
  const AppTopBarStatus({super.key, this.color, this.isReading});

  final Color? color;
  final bool Function()? isReading;

  @override
  Widget build(BuildContext context) {
    final scope = AppTopBarScope.maybeOf(context);
    Widget reading() {
      final phase = scope?.controller.refreshStatus.value;
      final busy = (isReading ?? scope?.isReading)?.call() ?? false;
      final pulling =
          phase == RefreshIndicatorStatus.drag ||
          phase == RefreshIndicatorStatus.armed;
      final refreshing =
          phase == RefreshIndicatorStatus.snap ||
          phase == RefreshIndicatorStatus.refresh;
      if (!busy && !pulling && !refreshing) return const SizedBox.shrink();
      final label = busy || refreshing
          ? '加载中'
          : phase == RefreshIndicatorStatus.armed
          ? '松开刷新'
          : '下拉刷新';
      return TweenAnimationBuilder<double>(
        key: const ValueKey('top-bar-page-activity'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 120),
        builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
        child: Tooltip(
          message: label,
          child: SizedBox.square(
            dimension: 40,
            child: Center(
              child: busy || refreshing
                  ? AppLoadingIndicator(
                      size: 16,
                      color: color,
                      semanticsLabel: label,
                    )
                  : Semantics(
                      label: label,
                      child: AnimatedRotation(
                        turns: phase == RefreshIndicatorStatus.armed ? .5 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          size: 20,
                          color: color,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (scope != null || isReading != null) Obx(reading),
        NetworkConnectionIndicator(foregroundColor: color),
      ],
    );
  }
}

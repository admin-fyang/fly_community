/// 全局统一的下拉刷新组件。
///
/// 本组件沿用 Flutter 官方 [RefreshIndicator] 的手势识别和刷新生命周期，
/// 接入 AppPageScaffold 时把手势与读取状态显示在公共顶栏；独立使用时
/// 保留局部 [AppLoadingIndicator]。页面原有滚动物理和 `onRefresh` 回调保持不变。
library;

import 'package:flutter/material.dart';

import 'app_loading_indicator.dart';
import '../navigation/app_top_bar.dart';

class AppRefreshIndicator extends StatefulWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  /// 页面原有的刷新回调；组件只负责呈现，不处理任何业务数据。
  final Future<void> Function() onRefresh;

  /// 必须是可滚动组件，空列表应搭配 [AlwaysScrollableScrollPhysics]。
  final Widget child;

  /// 嵌套滚动场景可通过该条件指定由哪一层滚动触发刷新。
  final ScrollNotificationPredicate notificationPredicate;

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

class _AppRefreshIndicatorState extends State<AppRefreshIndicator> {
  RefreshIndicatorStatus? _status;
  final _refreshOwner = Object();
  AppTopBarController? _topBarController;

  @override
  void dispose() {
    final controller = _topBarController;
    // 列表视图切换时撤销旧手势状态，但不能清除新视图已开始的刷新。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller?.setRefreshStatus(null, owner: _refreshOwner),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topBar = AppTopBarScope.maybeOf(context);
    _topBarController = topBar?.controller;
    // 已接入顶栏的页面把手势状态转发到局部 GetX 展示控制器，保留原刷新回调。
    if (topBar != null) {
      return RefreshIndicator.noSpinner(
        onRefresh: widget.onRefresh,
        notificationPredicate: widget.notificationPredicate,
        onStatusChange: (status) =>
            topBar.controller.setRefreshStatus(status, owner: _refreshOwner),
        child: widget.child,
      );
    }
    // 只有下拉手势正在形成或刷新任务正在执行时才显示顶部指示器。
    // canceled / done / null 都是已收敛状态；尤其 canceled 必须隐藏，
    // 否则用户下拉距离不足后松手会留下一个永久加载圈。
    final visible = switch (_status) {
      RefreshIndicatorStatus.drag ||
      RefreshIndicatorStatus.armed ||
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh => true,
      RefreshIndicatorStatus.canceled ||
      RefreshIndicatorStatus.done ||
      null => false,
    };

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          notificationPredicate: widget.notificationPredicate,
          onStatusChange: (status) {
            if (!mounted || status == _status) return;
            setState(() => _status = status);
          },
          child: widget.child,
        ),
        IgnorePointer(
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: visible
                  ? const Padding(
                      key: ValueKey('app-refresh-loading'),
                      padding: EdgeInsets.only(top: 10),
                      child: AppLoadingIndicator(),
                    )
                  : const SizedBox.shrink(key: ValueKey('app-refresh-idle')),
            ),
          ),
        ),
      ],
    );
  }
}

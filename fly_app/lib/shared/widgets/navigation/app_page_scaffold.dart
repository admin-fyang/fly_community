/// 带固定顶栏的页面骨架。只处理展示作用域、安全区与内容遮挡，不处理业务请求。
library;

import 'page_read_activity.dart';
import '../../../core/extensions/context_extension.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

import 'app_top_bar.dart';

export 'app_top_bar.dart';

/// 保留 Scaffold 的现有底栏、浮动按钮及键盘行为，同时统一顶栏固定定位。
///
/// [extendBodyBehindAppBar] 为 true 时，调用方必须在主滚动内容内部加入
/// [appTopBarInset]；沉浸式视频/扫码页面无需加入空白。为 false 时由骨架
/// 统一避让顶栏，适用于表单外的固定布局，避免覆盖页面操作。
class AppPageScaffold extends StatefulWidget {
  const AppPageScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.isReading,
    this.readActivity,
    this.topContentGap = 0,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? drawer;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool Function()? isReading;
  final PageReadActivity? readActivity;

  /// 内容原有的顶部留白，用于等到真实内容越过顶栏底边才开启磨砂。
  final double topContentGap;

  @override
  State<AppPageScaffold> createState() => _AppPageScaffoldState();
}

class _AppPageScaffoldState extends State<AppPageScaffold> {
  final _controller = AppTopBarController();
  final _barKey = GlobalKey();
  int _scrollRevision = 0;
  BuildContext? _scrollSource;

  void _onMetrics(ScrollMetrics metrics, BuildContext? source) {
    if (metrics.axis != Axis.vertical || !widget.extendBodyBehindAppBar) return;
    _scrollSource = source;
    final revision = ++_scrollRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _scrollRevision) return;
      // 骨架与真实列表可能在同一帧切换；过期视口不能再访问 RenderObject。
      if (source == null || !source.mounted) {
        _controller.setOverlap(false);
        return;
      }
      final bar = _barKey.currentContext?.findRenderObject();
      final viewport = source.findRenderObject();
      if (bar is! RenderBox ||
          viewport is! RenderBox ||
          !bar.hasSize ||
          !viewport.hasSize) {
        return;
      }
      final barBottom = bar.localToGlobal(Offset(0, bar.size.height)).dy;
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      // 视口本身未延伸到顶栏下方时，嵌套列表滚动不能误触发背景变化。
      final underlap = viewportTop < barBottom - .5;
      final topDistance = metrics.axisDirection == AxisDirection.up
          ? metrics.extentAfter
          : metrics.extentBefore;
      _controller.setOverlap(
        underlap && topDistance > widget.topContentGap + .5,
      );
    });
  }

  @override
  void didUpdateWidget(AppPageScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.extendBodyBehindAppBar || _scrollSource?.mounted != true) {
        _controller.setOverlap(false);
      }
    });
  }

  @override
  void dispose() {
    _controller.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = widget.appBar;
    final topInset = bar == null
        ? 0.0
        : appTopBarInset(context, height: bar.preferredSize.height);
    return AppTopBarScope(
      controller: _controller,
      topInset: topInset,
      isReading:
          widget.isReading ??
          (widget.readActivity == null
              ? null
              : () => widget.readActivity!.isReading),
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        extendBody: widget.extendBody,
        extendBodyBehindAppBar: bar != null,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        appBar: bar == null
            ? null
            : PreferredSize(
                preferredSize: bar.preferredSize,
                child: SizedBox(key: _barKey, child: bar),
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) {
                  _onMetrics(notification.metrics, notification.context);
                }
                return false;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0) {
                    _onMetrics(notification.metrics, notification.context);
                  }
                  return false;
                },
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.paddingOf(
                        context,
                      ).copyWith(top: bar == null ? null : 0),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: widget.extendBodyBehindAppBar ? 0 : topInset,
                      ),
                      child: widget.body,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.readActivity != null)
              Positioned(
                top: topInset + 8,
                left: 16,
                right: 16,
                child: _PageReadError(activity: widget.readActivity!),
              ),
          ],
        ),
        bottomNavigationBar: widget.bottomNavigationBar,
        floatingActionButton: widget.floatingActionButton,
        floatingActionButtonLocation: widget.floatingActionButtonLocation,
        drawer: widget.drawer,
      ),
    );
  }
}

/// 读取失败使用页面内的可关闭文案；不弹 Toast，不改变主列表滚动尺寸。
class _PageReadError extends StatelessWidget {
  const _PageReadError({required this.activity});
  final PageReadActivity activity;

  @override
  Widget build(BuildContext context) => Obx(() {
    final message = activity.errorMessage.value;
    if (message.isEmpty) return const SizedBox.shrink();
    final semantic = context.semanticColors;
    return Material(
      color: semantic.surface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: semantic.destructive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: semantic.textPrimary),
              ),
            ),
            IconButton(
              tooltip: '关闭提示',
              onPressed: activity.dismissError,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  });
}

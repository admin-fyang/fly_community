/// 顶部 Toast 提示。
///
/// 样式参考 `资料/UI/其它/顶部 Toast 提示组件.html`：顶部居中、半透明表面、
/// 轻描边、左侧状态图标、紧凑文字。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import 'app_overlay_coordinator.dart';

enum AppToastType { success, warning, error, info }
enum AppToastPlacement { top, center }

class AppToast {
  AppToast._();

  static const AppOverlayChannel _channel = AppOverlayChannel.toast;
  static _AppToastHostState? _hostState;
  static _ToastRequest? _latestRequest;

  static void success(String message) =>
      show(message, type: AppToastType.success);

  static void warning(String message) =>
      show(message, type: AppToastType.warning);

  static void error(String message) => show(message, type: AppToastType.error);

  static void errorCenter(String message) => show(
    message,
    type: AppToastType.error,
    placement: AppToastPlacement.center,
  );

  static void info(String message) => show(message, type: AppToastType.info);

  static void show(
    String message, {
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 2),
    AppToastPlacement placement = AppToastPlacement.top,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;

    final context = Get.overlayContext ?? Get.context;
    if (context == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final request = _ToastRequest(
      message: normalized,
      type: type,
      duration: duration,
      placement: placement,
    );
    final coordinator = AppOverlayCoordinator.instance;
    _latestRequest = request;

    if (coordinator.isActive(_channel)) {
      final hostState = _hostState;
      if (hostState != null && hostState.mounted) {
        hostState.update(request);
      }
      // The entry can exist for one frame before its State is mounted. The host
      // reads [_latestRequest] during initState, so a second entry is not needed
      // for a burst of toasts in that window.
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AppToastHost(
        request: request,
        onMounted: (state) {
          _hostState = state;
        },
        onDisposed: (state) {
          if (identical(_hostState, state)) _hostState = null;
        },
        onDismissed: () {
          coordinator.remove(_channel, expected: entry);
          if (!coordinator.isActive(_channel)) {
            _latestRequest = null;
          }
        },
      ),
    );
    if (!coordinator.show(channel: _channel, overlay: overlay, entry: entry) &&
        identical(_latestRequest, request)) {
      _latestRequest = null;
    }
  }

  static IconData _icon(AppToastType type) {
    return switch (type) {
      AppToastType.success => Icons.check_circle,
      AppToastType.warning => Icons.warning,
      AppToastType.error => Icons.error,
      AppToastType.info => Icons.info,
    };
  }

  static Color _iconColor(BuildContext context, AppToastType type) {
    return switch (type) {
      AppToastType.success => context.tokens.online,
      AppToastType.warning => const Color(0xFFFF9F0A),
      AppToastType.error => context.tokens.danger,
      AppToastType.info => context.tokens.brand,
    };
  }
}

class _ToastRequest {
  const _ToastRequest({
    required this.message,
    required this.type,
    required this.duration,
    required this.placement,
  });

  final String message;
  final AppToastType type;
  final Duration duration;
  final AppToastPlacement placement;
}

class _AppToastHost extends StatefulWidget {
  const _AppToastHost({
    required this.request,
    required this.onMounted,
    required this.onDisposed,
    required this.onDismissed,
  });

  final _ToastRequest request;
  final ValueChanged<_AppToastHostState> onMounted;
  final ValueChanged<_AppToastHostState> onDisposed;
  final VoidCallback onDismissed;

  @override
  State<_AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<_AppToastHost>
    with SingleTickerProviderStateMixin {
  late _ToastRequest _request = AppToast._latestRequest ?? widget.request;
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _dismissTimer;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.2),
      end: Offset.zero,
    ).animate(curved);
    widget.onMounted(this);
    _controller.forward();
    _scheduleDismiss();
  }

  void update(_ToastRequest request) {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _isRemoving = false;
    if (_controller.status == AnimationStatus.reverse) {
      _controller.forward();
    }
    if (_request.message == request.message && _request.type == request.type) {
      _request = request;
    } else {
      setState(() => _request = request);
    }
    _scheduleDismiss();
  }

  void _scheduleDismiss() {
    _dismissTimer = Timer(_request.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted || _isRemoving) return;
    _isRemoving = true;
    _dismissTimer?.cancel();
    _controller.reverse().whenCompleteOrCancel(() {
      if (!mounted ||
          !_isRemoving ||
          _controller.status != AnimationStatus.dismissed) {
        return;
      }
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    widget.onDisposed(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final toast = IgnorePointer(
          child: SlideTransition(
            position: _offset,
            child: FadeTransition(
              opacity: _opacity,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 384),
                  child: Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.92,
                        ),
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                        border: Border.all(
                          color: context.tokens.divider.withValues(alpha: 0.45),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSizes.paddingMd),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: Row(
                            key: ValueKey('${_request.type}:${_request.message}'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AppToast._icon(_request.type),
                                size: 22,
                                color: AppToast._iconColor(context, _request.type),
                              ),
                              const SizedBox(width: AppSizes.paddingMd),
                              Flexible(
                                child: Text(
                                  _request.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.listTitle.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    if (_request.placement == AppToastPlacement.center) {
      return Positioned.fill(
        child: SafeArea(child: Align(alignment: Alignment.center, child: toast)),
      );
    }
    return Positioned(
      top: AppSizes.paddingXl,
      left: AppSizes.paddingLg,
      right: AppSizes.paddingLg,
      child: SafeArea(bottom: false, child: toast),
    );
  }
}

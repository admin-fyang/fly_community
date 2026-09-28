/// Lightweight press feedback primitive used by Telegram-inspired list/surface UI.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_motion.dart';

class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.normalColor = Colors.transparent,
    this.pressedColor,
    this.borderRadius = BorderRadius.zero,
    this.scaleWhenPressed = 1,
    this.releasePressedOnLongPress = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Presentation-only long-press hook.
  ///
  /// Additive API: existing call sites are unaffected. This lets list rows
  /// share the same press language without falling back to InkWell.
  final VoidCallback? onLongPress;

  final String? semanticLabel;
  final Color normalColor;
  final Color? pressedColor;
  final BorderRadius borderRadius;

  /// Keep list rows at 1.0. Small standalone surfaces may use ~0.99.
  final double scaleWhenPressed;

  /// Immediately clears the visual pressed state when a long press fires.
  ///
  /// Context menus are usually pushed before the pointer is released, so the
  /// original gesture route may not receive [onLongPressEnd]. Keep this off by
  /// default and enable it only for rows whose long press opens a new overlay.
  final bool releasePressedOnLongPress;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final pressedColor =
        widget.pressedColor ?? context.semanticColors.surfacePressed;

    return Semantics(
      button: widget.onTap != null,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (widget.releasePressedOnLongPress) {
                  _setPressed(false);
                }
                widget.onLongPress!();
              },
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        // 长按识别器接管手势时，点击识别器会先触发 onTapCancel。
        // 先恢复按压反馈；若打开 Context Menu，onLongPress 会按配置立即释放。
        onLongPressStart: widget.onLongPress != null
            ? (_) => _setPressed(true)
            : null,
        onLongPressEnd: widget.onLongPress != null
            ? (_) => _setPressed(false)
            : null,
        child: AnimatedScale(
          scale: _pressed ? widget.scaleWhenPressed : 1,
          duration: AppConstants.animFast,
          curve: AppMotion.exit,
          child: AnimatedContainer(
            duration: AppConstants.animFast,
            curve: AppMotion.exit,
            decoration: BoxDecoration(
              color: _pressed ? pressedColor : widget.normalColor,
              borderRadius: widget.borderRadius,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

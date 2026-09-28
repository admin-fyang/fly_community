/// Compact navigation button with Telegram-like optical sizing and press state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_motion.dart';

class AppNavigationButton extends StatefulWidget {
  const AppNavigationButton({
    super.key,
    this.icon,
    this.svgAsset,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.iconSize = 21,
    this.size = 40,
  }) : assert(
         (icon == null) != (svgAsset == null),
         'icon 与 svgAsset 必须且只能提供一个',
       );

  /// Material 图标；与 [svgAsset] 二选一。
  final IconData? icon;

  /// SVG 资源路径；统一继承按钮的主题色、禁用色和按压动画。
  final String? svgAsset;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double iconSize;
  final double size;

  @override
  State<AppNavigationButton> createState() => _AppNavigationButtonState();
}

class _AppNavigationButtonState extends State<AppNavigationButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final enabled = widget.onPressed != null;
    final foreground = widget.color ?? semantic.textPrimary;
    // Telegram-iOS Night / PresentationThemeRootNavigationBar:
    // disabledButtonColor = #525252. Navigation controls intentionally use a
    // darker disabled role than ordinary list text (#8F8F8F).
    final disabledForeground = context.isDark
        ? const Color(0xFF525252)
        : semantic.textDisabled;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        child: SizedBox.square(
          dimension: widget.size,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.94 : 1,
              duration: AppConstants.animFast,
              curve: AppMotion.exit,
              child: AnimatedContainer(
                duration: AppConstants.animFast,
                curve: AppMotion.exit,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed
                      ? semantic.surfacePressed.withValues(alpha: 0.60)
                      : Colors.transparent,
                ),
                child: widget.svgAsset == null
                    ? Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: enabled ? foreground : disabledForeground,
                      )
                    : Center(
                        child: SvgPicture.asset(
                          widget.svgAsset!,
                          width: widget.iconSize,
                          height: widget.iconSize,
                          colorFilter: ColorFilter.mode(
                            enabled ? foreground : disabledForeground,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip == null || widget.tooltip!.isEmpty) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

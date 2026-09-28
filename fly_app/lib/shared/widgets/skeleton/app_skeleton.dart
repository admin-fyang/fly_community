/// 全局骨架屏基础组件。
///
/// [AppSkeletonScope] 统一管理辅助动画，[AppSkeletonBlock] 只负责绘制实体占位形状。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';

/// 骨架屏动画容器。
///
/// 子节点应使用不透明实体形状，由这里的 ShaderMask 统一填充流动渐变，
/// 避免每个页面重复维护 AnimationController 和渐变变换逻辑。
class AppSkeletonScope extends StatefulWidget {
  const AppSkeletonScope({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 3500),
    this.angle = 3.141592653589793 / 4,
    this.dimAlpha = 0.15,
    this.brightAlpha = 0.32,
  });

  final Widget child;
  final Duration duration;
  final double angle;
  final double dimAlpha;
  final double brightAlpha;

  @override
  State<AppSkeletonScope> createState() => _AppSkeletonScopeState();
}

class _AppSkeletonScopeState extends State<AppSkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(AppSkeletonScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dimColor = colors.onSurfaceVariant.withValues(alpha: widget.dimAlpha);
    final brightColor = colors.onSurfaceVariant.withValues(
      alpha: widget.brightAlpha,
    );

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [dimColor, brightColor, dimColor, brightColor, dimColor],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              tileMode: TileMode.repeated,
              transform: _SkeletonGradientTransform(
                percent: _controller.value,
                angle: widget.angle,
              ),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// 骨架屏基础占位块。
///
/// 颜色固定为不透明黑色，实际可见颜色由 [AppSkeletonScope] 的 ShaderMask 决定。
class AppSkeletonBlock extends StatelessWidget {
  const AppSkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
  });

  const AppSkeletonBlock.circle({super.key, required double size})
    : width = size,
      height = size,
      shape = BoxShape.circle,
      borderRadius = null;

  final double width;
  final double height;
  final BoxShape shape;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : borderRadius ?? BorderRadius.circular(AppSizes.radiusSm),
      ),
    );
  }
}

class _SkeletonGradientTransform extends GradientTransform {
  const _SkeletonGradientTransform({
    required this.percent,
    required this.angle,
  });

  final double percent;
  final double angle;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final centerX = bounds.width / 2;
    final centerY = bounds.height / 2;

    return Matrix4.identity()
      ..translateByDouble(centerX, centerY, 0, 1)
      ..rotateZ(angle)
      ..translateByDouble(-centerX, -centerY, 0, 1)
      ..translateByDouble(bounds.width * percent, 0, 0, 1);
  }
}

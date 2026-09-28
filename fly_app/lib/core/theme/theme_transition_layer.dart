/// 全局主题圆形扩散过渡层。
///
/// 切换前截取当前界面，真实新主题在底层立即生效；随后从用户点击位置逐步
/// 裁掉旧主题快照，使完整的新主题界面以圆形扩散方式显现。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/enums/theme_mode_type.dart';
import 'theme_controller.dart';

class ThemeTransitionLayer extends StatefulWidget {
  const ThemeTransitionLayer({
    super.key,
    required this.controller,
    required this.child,
  });

  final ThemeController controller;
  final Widget child;

  static ThemeTransitionLayerState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_ThemeTransitionScope>();
    assert(scope != null, 'ThemeTransitionLayer 未挂载到应用根节点');
    return scope!.state;
  }

  @override
  State<ThemeTransitionLayer> createState() => ThemeTransitionLayerState();
}

class ThemeTransitionLayerState extends State<ThemeTransitionLayer>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1080);

  final _boundaryKey = GlobalKey();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: _duration,
  );
  ui.Image? _oldFrame;
  Offset _origin = Offset.zero;
  bool _switching = false;

  /// 从指定的全局坐标开始切换主题；动画期间忽略重复操作，防止快照相互覆盖。
  Future<void> changeTheme(
    ThemeModeType mode, {
    required Offset origin,
  }) async {
    if (_switching || mode == widget.controller.mode) return;

    final targetBrightness = switch (mode) {
      ThemeModeType.light => Brightness.light,
      ThemeModeType.dark => Brightness.dark,
      ThemeModeType.system =>
        View.of(context).platformDispatcher.platformBrightness,
    };
    if (targetBrightness == Theme.of(context).brightness) {
      await widget.controller.setMode(mode);
      return;
    }

    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) {
      await widget.controller.setMode(mode);
      return;
    }

    _switching = true;
    try {
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      final frame = await boundary.toImage(pixelRatio: pixelRatio);
      if (!mounted) {
        frame.dispose();
        return;
      }
      _oldFrame?.dispose();
      setState(() {
        _oldFrame = frame;
        _origin = origin;
      });
      await widget.controller.setMode(mode);
      if (!mounted) return;
      await _animation.forward(from: 0);
    } finally {
      if (mounted) {
        setState(() {
          _oldFrame?.dispose();
          _oldFrame = null;
        });
      }
      _switching = false;
    }
  }

  @override
  void dispose() {
    _oldFrame?.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ThemeTransitionScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(key: _boundaryKey, child: widget.child),
          if (_oldFrame != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, _) => ClipPath(
                    clipper: _OldThemeRevealClipper(
                      origin: _origin,
                      progress: Curves.easeInOutCubic.transform(
                        _animation.value,
                      ),
                    ),
                    child: RawImage(image: _oldFrame, fit: BoxFit.fill),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeTransitionScope extends InheritedWidget {
  const _ThemeTransitionScope({required this.state, required super.child});

  final ThemeTransitionLayerState state;

  @override
  bool updateShouldNotify(_ThemeTransitionScope oldWidget) => false;
}

/// 保留圆形区域外的旧主题快照，圆内区域显示底层已经生效的新主题。
class _OldThemeRevealClipper extends CustomClipper<Path> {
  const _OldThemeRevealClipper({
    required this.origin,
    required this.progress,
  });

  final Offset origin;
  final double progress;

  @override
  Path getClip(Size size) {
    final farthestX = math.max(origin.dx, size.width - origin.dx);
    final farthestY = math.max(origin.dy, size.height - origin.dy);
    final radius = math.sqrt(farthestX * farthestX + farthestY * farthestY);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: origin, radius: radius * progress));
  }

  @override
  bool shouldReclip(_OldThemeRevealClipper oldClipper) =>
      origin != oldClipper.origin || progress != oldClipper.progress;
}

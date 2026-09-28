import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AirplaneFloat extends StatefulWidget {
  const AirplaneFloat({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AirplaneFloat> createState() => _AirplaneFloatState();
}

class _AirplaneFloatState extends State<AirplaneFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  final _random = math.Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _nextDuration(),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 每一轮周期略有变化，避免机械重复
        _controller.duration = _nextDuration();
        _controller.forward(from: 0);
      }
    });

    _controller.forward();
  }

  Duration _nextDuration() {
    // 1.6 ～ 2.4 秒
    return Duration(
      milliseconds: 1600 + _random.nextInt(801),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;

        final state = _airFlow(t);

        return Transform.translate(
          offset: Offset(state.dx, state.dy),
          child: Transform.rotate(
            angle: state.rotation * math.pi / 180,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }

  _AirState _airFlow(double t) {
    // 关键帧：
    //
    // 0%    原位
    // 18%   Y ↑ 0.4px
    // 36%   旋转 +0.8°
    // 56%   Y ↓ 0.6px
    // 72%   旋转 -0.6°
    // 86%   X +0.3px
    // 100%  恢复

    final dx = _keyframe(
      t,
      const [
        _Point(0.00, 0.0),
        _Point(0.18, 0.0),
        _Point(0.36, 0.0),
        _Point(0.56, 0.0),
        _Point(0.72, 0.0),
        _Point(0.86, 0.3),
        _Point(1.00, 0.0),
      ],
    );

    final dy = _keyframe(
      t,
      const [
        _Point(0.00, 0.0),
        _Point(0.18, -0.4),
        _Point(0.36, -0.25),
        _Point(0.56, 0.6),
        _Point(0.72, 0.35),
        _Point(0.86, 0.1),
        _Point(1.00, 0.0),
      ],
    );

    final rotation = _keyframe(
      t,
      const [
        _Point(0.00, 0.0),
        _Point(0.18, 0.15),
        _Point(0.36, 0.8),
        _Point(0.56, 0.2),
        _Point(0.72, -0.6),
        _Point(0.86, -0.15),
        _Point(1.00, 0.0),
      ],
    );

    return _AirState(
      dx: dx,
      dy: dy,
      rotation: rotation,
    );
  }

  double _keyframe(double t, List<_Point> points) {
    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];

      if (t >= from.time && t <= to.time) {
        final localT =
            (t - from.time) / (to.time - from.time);

        // 非线性缓动，去掉“机械匀速感”
        final eased = Curves.easeInOutSine.transform(localT);

        return from.value +
            (to.value - from.value) * eased;
      }
    }

    return points.last.value;
  }
}

class _Point {
  final double time;
  final double value;

  const _Point(this.time, this.value);
}

class _AirState {
  final double dx;
  final double dy;
  final double rotation;

  const _AirState({
    required this.dx,
    required this.dy,
    required this.rotation,
  });
}
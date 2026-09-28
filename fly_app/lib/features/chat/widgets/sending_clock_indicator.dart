/// 发送中状态的轻量动画小时钟。
library;

import 'package:flutter/material.dart';

/// 只使用旋转变换驱动小时钟，不触发布局和尺寸重算。
///
/// 基础文本、图片和文件气泡由 Flyer 组件自带的旋转进度指示器负责；富消息
/// 气泡统一复用本组件，让所有发送中状态都具有持续且克制的动态反馈。
class SendingClockIndicator extends StatefulWidget {
  const SendingClockIndicator({
    super.key,
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  State<SendingClockIndicator> createState() => _SendingClockIndicatorState();
}

class _SendingClockIndicatorState extends State<SendingClockIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '发送中',
    child: RepaintBoundary(
      child: RotationTransition(
        turns: _controller,
        child: Icon(Icons.schedule, size: widget.size, color: widget.color),
      ),
    ),
  );
}

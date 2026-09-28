/// 全局统一的 Cupertino 风格确定进度圆环。
///
/// Flutter 的 [CupertinoActivityIndicator] 仅表示“正在处理”，不能表达确定
/// 进度。本组件使用圆角端点的轻量圆环补足这一能力：大尺寸在圆心显示百分比，
/// 小于 36px 的紧凑场景只绘制圆环，避免文字因空间不足而不可读。
library;

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/extensions/context_extension.dart';

class AppCupertinoProgressIndicator extends StatelessWidget {
  const AppCupertinoProgressIndicator({
    super.key,
    required this.progress,
    this.size = 40,
    this.strokeWidth,
    this.color,
    this.trackColor,
    this.showPercentage = true,
    this.semanticsLabel = '当前进度',
  });

  /// 业务层传入的原始进度，组件内部统一限制到 0～1，防止异常值破坏绘制。
  final double progress;

  /// 组件外径；达到 36px 时才具备显示百分比的最小可读空间。
  final double size;

  /// 可按覆盖层尺寸微调线宽；未传入时按尺寸自适应并限制在 2～4px。
  final double? strokeWidth;

  /// 已完成进度颜色，默认使用当前主题强调色。
  final Color? color;

  /// 未完成轨道颜色，默认由进度色降低透明度得到。
  final Color? trackColor;

  /// 暂停等需要在圆心展示操作图标的场景，可以关闭百分比文字。
  final bool showPercentage;

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final progressColor = color ?? context.semanticColors.accent;
    final effectiveStroke =
        strokeWidth ?? (size * 0.075).clamp(2.0, 4.0).toDouble();
    final displayPercentage = showPercentage && size >= 36;
    final percentage = (value * 100).round();

    return Semantics(
      label: semanticsLabel,
      value: '$percentage%',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _CupertinoProgressPainter(
            progress: value,
            strokeWidth: effectiveStroke,
            color: progressColor,
            trackColor: trackColor ?? progressColor.withValues(alpha: 0.22),
          ),
          child: displayPercentage
              ? Center(
                  child: Text(
                    '$percentage%',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: progressColor,
                      fontSize: (size * 0.23).clamp(8.0, 12.0),
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: -0.4,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _CupertinoProgressPainter extends CustomPainter {
  const _CupertinoProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        bounds,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CupertinoProgressPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      strokeWidth != oldDelegate.strokeWidth ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor;
}

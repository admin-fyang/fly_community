/// Telegram Web 风格的“正文 + 右浮动元信息”布局。
///
/// CSS 的 `float: right` 既不是固定左右两列，也不是简单紧跟正文：
/// 短消息保持紧凑；多行消息把元信息定位到末行右侧；空间不足时元信息整组换行。
///
/// 这里刻意不把元信息作为 [WidgetSpan] 塞回正文。不同渲染器对恰好
/// 填满行宽的 WidgetSpan 有不同的舍入结果，会导致真机把时间错误挤到下一行。
/// 正文与元信息分别布局，位置统一由同一个 [TextPainter] 的行度量决定。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';

class TelegramInlineContent extends StatelessWidget {
  const TelegramInlineContent({
    super.key,
    required this.text,
    required this.style,
    required this.metadata,
    required this.metadataWidth,
    this.minimumWidth = 0,
    this.leading,
    this.leadingSize = Size.zero,
    this.inlineSpans,
  });

  final String text;
  final TextStyle style;
  final Widget metadata;
  final double metadataWidth;
  final double minimumWidth;
  final Widget? leading;
  final Size leadingSize;
  final List<InlineSpan>? inlineSpans;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    // Text Widget 会自动继承 DefaultTextStyle（包括 Material 的字距），
    // TextPainter 不会。两者必须显式使用同一份完整样式，否则长文本每个字符
    // 累积约 0.25px 测量误差，最终会错误判断末行是否容得下时间。
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSpan = _baseSpan(resolvedStyle);
        final painter = TextPainter(
          text: baseSpan,
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
        );
        _setLeadingPlaceholder(painter);
        painter.layout();

        final naturalWidth =
            painter.width + AppSizes.telegramMessageMetaGap + metadataWidth;
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : naturalWidth;
        final targetWidth = math.min(
          maxWidth,
          math.max(naturalWidth, minimumWidth),
        );

        painter.layout(maxWidth: targetWidth);
        final lines = painter.computeLineMetrics();
        final lastLineWidth = lines.isEmpty ? 0.0 : lines.last.width;
        final remaining = math.max(0.0, targetWidth - lastLineWidth);
        final requiredInlineWidth =
            AppSizes.telegramMessageMetaGap + metadataWidth;
        final metadataNeedsOwnLine =
            remaining + AppSizes.telegramMessageLayoutTolerance <
            requiredInlineWidth;
        final textHeight = math.max(
          painter.height,
          painter.preferredLineHeight,
        );
        final contentHeight =
            textHeight +
            (metadataNeedsOwnLine ? AppSizes.telegramMessageMetaHeight : 0);
        final metadataTop = metadataNeedsOwnLine
            ? textHeight
            : textHeight - AppSizes.telegramMessageMetaHeight;

        return SizedBox(
          width: targetWidth,
          height: contentHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: SizedBox(
                    width: targetWidth,
                    child: Text.rich(
                      baseSpan,
                      textDirection: direction,
                      textScaler: scaler,
                      locale: locale,
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: metadataTop,
                end: 0,
                width: metadataWidth,
                height: AppSizes.telegramMessageMetaHeight,
                child: Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: metadata,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  TextSpan _baseSpan(TextStyle resolvedStyle) =>
      TextSpan(style: resolvedStyle, children: _baseChildren());

  List<InlineSpan> _baseChildren() => [
    if (leading != null)
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox.fromSize(size: leadingSize, child: leading),
      ),
    if (inlineSpans == null) TextSpan(text: text) else ...inlineSpans!,
  ];

  void _setLeadingPlaceholder(TextPainter painter) {
    if (leading == null) return;
    painter.setPlaceholderDimensions([
      PlaceholderDimensions(
        size: leadingSize,
        alignment: PlaceholderAlignment.middle,
      ),
    ]);
  }
}

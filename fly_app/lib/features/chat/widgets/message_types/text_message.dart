/// 文本消息组件。
///
/// 渲染纯文本气泡内容，包含引用回复摘要。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/message_model.dart';
import '../telegram_inline_content.dart';

/// 文本消息内容(置于标准气泡内)
class TextMessageContent extends StatelessWidget {
  const TextMessageContent({
    super.key,
    required this.message,
    required this.color,
    this.trailingMetadata,
    this.trailingMetadataWidth = 0,
    this.minimumContentWidth = 0,
    this.fontSize,
  });

  final MessageModel message;
  final Color color;
  final Widget? trailingMetadata;
  final double trailingMetadataWidth;
  final double minimumContentWidth;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTextStyles.messageBody.copyWith(
      color: color,
      fontSize: fontSize,
    );
    final displayText = message.text;
    return trailingMetadata == null
        ? Text(displayText, style: textStyle)
        : TelegramInlineContent(
          text: displayText,
          style: textStyle,
          metadata: trailingMetadata!,
          metadataWidth: trailingMetadataWidth,
          minimumWidth: minimumContentWidth,
        );
  }
}

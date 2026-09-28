/// 撤回消息组件。
///
/// 居中弱化提示「XX 撤回了一条消息」。
library;

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extension.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/recall_message_text.dart';
import '../../../../data/models/message_model.dart';

/// 撤回提示:居中淡字(无气泡)
class RecallMessage extends StatelessWidget {
  const RecallMessage({super.key, required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    // 撤回消息的 body_text 可能仍保留原正文，展示层不能再消费该字段，
    // 否则会把已经撤回的内容重新显示为系统提示。
    final text = recallMessageText(isMine: message.isMine);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: AppTextStyles.metadata.copyWith(
            color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

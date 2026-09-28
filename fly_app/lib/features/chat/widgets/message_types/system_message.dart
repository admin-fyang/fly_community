/// 系统消息组件。
///
/// 居中胶囊提示的系统消息(如入群提示)。
library;

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extension.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/message_model.dart';

/// 系统消息:居中胶囊提示
class SystemMessage extends StatelessWidget {
  const SystemMessage({super.key, required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        // padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color:
              context.isDark
                  ? const Color(0xFF1F1F1F)
                  : context.colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.6,
                  ),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: AppTextStyles.metadata.copyWith(
            color:
                context.isDark
                    ? const Color(0xFFFFFFFF)
                    : context.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

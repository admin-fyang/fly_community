/// 聊天引用回复预览条组件。
///
/// 输入栏上方展示被引用消息的发送者与摘要,可取消引用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/message_model.dart';

/// 输入框上方的回复预览条
///
/// 左侧品牌竖条 + 被回复者昵称 + 内容预览，右侧关闭按钮。
class ChatReplyPreview extends StatelessWidget {
  const ChatReplyPreview({
    super.key,
    required this.message,
    required this.onClose,
  });

  final MessageModel message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    // 单聊对方消息无 senderName，按身份兜底显示
    final name = message.senderName ?? (message.isMine ? '我' : '对方');
    final preview =
        message.text.isNotEmpty ? message.text : _typeLabel(message);

    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingLg,
        vertical: AppSizes.paddingSm,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: context.tokens.brand,
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          const SizedBox(width: AppSizes.paddingMd),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.badgeLabel.copyWith(
                    color: context.tokens.brand,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.metadata.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/chat/close.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                colors.onSurfaceVariant,
                BlendMode.srcIn,
              ),
            ),
            color: colors.onSurfaceVariant,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  String _typeLabel(MessageModel m) {
    final label = m.type.previewLabel;
    return label.isNotEmpty ? '[$label]' : '消息';
  }
}

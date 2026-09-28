/// 消息气泡分发组件。
///
/// 根据消息类型分发到 message_types 下的各类型渲染组件,并统一处理气泡
/// 底色、圆角、内边距与页脚(时间/状态)。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/chat_bubble_tokens.dart';
import '../../../core/utils/color_util.dart';
import '../../../core/utils/date_time_util.dart';
import '../../../data/enums/message_type.dart';
import '../../../data/enums/message_status.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/file_transfer_service.dart';
import '../../../data/services/im_pending_message_service.dart';
import '../chat_ui_design_adapter.dart';
import 'message_types/file_message.dart';
import 'message_types/image_message.dart';
import 'message_types/recall_message.dart';
import 'message_types/system_message.dart';
import 'message_types/text_message.dart';
import 'sending_clock_indicator.dart';

/// 消息气泡:布局外壳 + 按类型分发内容
///
/// 负责左右对齐、群聊头像/昵称、气泡底色与内边距、引用回复与时间脚注;
/// 各消息类型的具体渲染委托给 message_types/ 下的独立组件。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showSenderInfo = false,
    this.embeddedInChatLayout = false,
    this.onReplyTap,
    this.onRetryTap,
    this.onMediaTap,
    this.cachedImageBytes = const [],
    this.onImageDisplayed,
    this.onFileTap,
    this.onCallTap,
    this.fileTransferState = const FileTransferViewState(),
    this.attachmentUploadStates = const [],
    this.onAttachmentUploadToggle,
    this.showMessageStatus = true,
    this.messageTextSize,
    this.groupPosition = BubbleGroupPosition.single,
  });

  final MessageModel message;

  /// 群聊中对方消息:显示头像与昵称
  final bool showSenderInfo;

  /// flutter_chat_ui 已负责左右布局、头像和昵称时只渲染气泡本体。
  final bool embeddedInChatLayout;

  /// 引用点击只上报用户意图，定位和结果反馈由 Controller 处理。
  final ValueChanged<ReplyQuote>? onReplyTap;

  /// 只在自己的失败消息上启用，点击现有错误图标触发重试。
  final VoidCallback? onRetryTap;
  final ValueChanged<int>? onMediaTap;
  final List<Uint8List?> cachedImageBytes;
  final ValueChanged<int>? onImageDisplayed;
  final VoidCallback? onFileTap;
  final VoidCallback? onCallTap;
  final FileTransferViewState fileTransferState;
  final List<AttachmentUploadProgressState?> attachmentUploadStates;
  final ValueChanged<int>? onAttachmentUploadToggle;
  final bool showMessageStatus;

  /// 仅覆盖聊天消息正文的字号；时间、状态和卡片文本保持既有样式。
  final double? messageTextSize;

  /// Presentation-only grouping state; never stored in message data.
  final BubbleGroupPosition groupPosition;

  /// 卡片类消息:用中性底色(不随发送方变品牌色)、内容自带内边距
  bool get _isCard => message.type == MessageType.file;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return SystemMessage(message: message);
    if (message.isRecall) return RecallMessage(message: message);

    final mine = message.isMine;
    final bubble = ConstrainedBox(
      constraints: message.type == MessageType.text
          ? ChatUiDesignAdapter.messageConstraints(context)
          : ChatUiDesignAdapter.nonTextMessageConstraints(context),
      child: _bubble(context),
    );

    if (embeddedInChatLayout) return bubble;

    // 群聊对方:头像 +（昵称 + 气泡）
    if (showSenderInfo && !mine) {
      final name = message.senderName ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.bubbleGapDiff),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                right: AppSizes.paddingSm,
                bottom: 2,
              ),
              child: _SmallAvatar(name: name),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      name,
                      style: AppTextStyles.badgeLabel.copyWith(
                        color: ColorUtil.fromText(name),
                      ),
                    ),
                  ),
                  bubble,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.bubbleGapDiff),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }

  BorderRadius _radius() {
    return ChatUiDesignAdapter.bubbleRadius(
      isSentByMe: message.isMine,
      groupPosition: groupPosition,
    );
  }

  Widget _bubble(BuildContext context) {
    // 图片和视频本身就是消息容器，不再叠加普通气泡背景。时间与发送状态
    // 参照 flutter_chat_ui 图片消息覆盖在媒体右下角。
    if (message.type == MessageType.image) {
      return _mediaMessage(context);
    }

    final bubbles = context.chatBubbleTokens;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
    final mine = message.isMine;
    // 卡片类保持中性 surface；普通发出消息使用主题蓝，接收消息使用克制的
    // incoming surface。业务消息类型与交互契约保持不变。
    final neutral = _isCard;
    final fg = mine && !neutral ? bubbles.textOutgoing : bubbles.textIncoming;

    // 文字使用标准内边距，保证相同行数下的气泡高度一致。
    final pad = switch (message.type) {
      MessageType.text => const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingMd,
        vertical: AppSizes.paddingMd,
      ),
      _ => const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    };

    // 社区版消息由统一 footer 展示时间与发送状态。
    const showFooter = true;
    final usesInlineMetadata =
        showFooter &&
        message.type == MessageType.text;
    final inlineMetadata = usesInlineMetadata
        ? _footer(context, fg, inline: true)
        : null;
    final inlineMetadataWidth = usesInlineMetadata
        ? _footerWidth(context, fg)
        : 0.0;

    final outgoingColor = context.tokens.brand;
    final decoration = neutral
        ? BoxDecoration(
            color: bubbles.cardFill,
            borderRadius: _radius(),
            border: Border.all(
              color: bubbles.cardStroke,
              width: hairline,
            ),
          )
        : mine
        ? BoxDecoration(
            color: outgoingColor,
            borderRadius: _radius(),
          )
        : BoxDecoration(
            color: bubbles.incomingFill,
            borderRadius: _radius(),
            border: Border.all(
              color: bubbles.incomingStroke,
              width: hairline,
            ),
          );

    final coreBubble = Container(
      padding: pad,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        // 气泡宽度由内容决定；文字/通话的元信息进入正文流，
        // 其他类型仍由独立页脚贴齐右边缘。
        // 回复正文必须从引用块左边缘开始；未回复消息保持原有布局。
        crossAxisAlignment: message.reply == null
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.reply != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _replyQuote(context, fg),
            ),
          _content(
            fg,
            trailingMetadata: inlineMetadata,
            trailingMetadataWidth: inlineMetadataWidth,
            minimumContentWidth: message.reply == null
                ? 0
                : _replyQuoteWidth(context, fg),
          ),
          if (showFooter &&
              message.type != MessageType.text)
            Align(
              alignment: Alignment.centerRight,
              child: _footer(context, fg),
            ),
        ],
      ),
    );

    return coreBubble;
  }

  Widget _mediaMessage(BuildContext context) {
    final media = ClipRRect(
      borderRadius: _radius(),
      child: Stack(
        children: [
          _content(Colors.white),
          if (message.reply != null)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.chatBubbleTokens.mediaMetaOverlay,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _replyQuote(context, Colors.white),
              ),
            ),
          Positioned(right: 8, bottom: 8, child: _mediaFooter(context)),
        ],
      ),
    );
    return media;
  }

  Widget _mediaFooter(BuildContext context) {
    final status = message.status;
    final statusIcon = status.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0x4D000000)
            : context.chatBubbleTokens.mediaMetaOverlay,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateTimeUtil.messageTime(message.time),
            style: AppTextStyles.badgeLabel.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (showMessageStatus &&
              message.isMine &&
              status != MessageStatus.failed &&
              statusIcon != null) ...[
            const SizedBox(width: 3),
            if (status == MessageStatus.sending)
              const SendingClockIndicator(color: Colors.white, size: 13)
            else
              Semantics(
                label: status.name,
                child: Icon(statusIcon, size: 13, color: Colors.white),
              ),
          ],
        ],
      ),
    );
  }

  /// 按类型分发到独立内容组件
  Widget _content(
    Color fg, {
    Widget? trailingMetadata,
    double trailingMetadataWidth = 0,
    double minimumContentWidth = 0,
  }) {
    switch (message.type) {
      case MessageType.image:
        return ImageMessageContent(
          message: message,
          onTap: onMediaTap,
          cachedBytes: cachedImageBytes,
          onDisplayed: onImageDisplayed,
          uploadStates: attachmentUploadStates,
          onUploadToggle: onAttachmentUploadToggle,
        );
      case MessageType.file:
        return FileMessageContent(
          message: message,
          color: fg,
          transferState: fileTransferState,
          onTap: onFileTap,
        );
      case MessageType.text:
      case MessageType.recall:
      case MessageType.system:
        return TextMessageContent(
          message: message,
          color: fg,
          fontSize: messageTextSize,
          trailingMetadata: trailingMetadata,
          trailingMetadataWidth: trailingMetadataWidth,
          minimumContentWidth: minimumContentWidth,
        );
    }
  }

  Widget _replyQuote(BuildContext context, Color fg) {
    final q = message.reply!;
    // 仅图片引用显示缩略图，其余类型使用文字摘要。
    final showsThumbnail =
        q.isAvailable &&
        q.preview != null &&
        const {
          MessageType.image,
        }.contains(q.preview!.kind);
    return InkWell(
      onTap: onReplyTap == null || q.messageId == null
          ? null
          : () => onReplyTap!(q),
      borderRadius: BorderRadius.circular(2),
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 4),
        padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
        decoration: BoxDecoration(
          // 引用关系只由左侧标识线表达，不再叠加背景色块。
          border: Border(
            left: BorderSide(
              color: context.chatBubbleTokens.replyAccent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showsThumbnail) ...[
              _ReplyThumbnail(preview: q.preview!, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    q.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.badgeLabel.copyWith(
                      // 对方白色气泡继续使用品牌色；我方品牌色气泡改用当前
                      // 气泡前景色，避免“蓝底蓝字”导致引用发送者不清晰。
                      color: message.isMine
                          ? fg
                          : context.chatBubbleTokens.replyAccent,
                    ),
                  ),
                  Text(
                    q.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.metadata.copyWith(
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 计算引用块的自然宽度，使较短的回复正文也能把时间贴到气泡右边缘。
  ///
  /// 这里只测量两行引用文字；媒体缩略图按组件的固定占位宽度补入。最终宽度
  /// 仍会被消息气泡的最大宽度约束，不会撑破窄屏布局。
  double _replyQuoteWidth(BuildContext context, Color fg) {
    final q = message.reply!;
    final senderStyle = DefaultTextStyle.of(context).style.merge(
      AppTextStyles.badgeLabel.copyWith(
        color: message.isMine
            ? fg
            : context.chatBubbleTokens.replyAccent,
      ),
    );
    final summaryStyle = DefaultTextStyle.of(context).style.merge(
      AppTextStyles.metadata.copyWith(
        color: fg.withValues(alpha: 0.75),
      ),
    );
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      return painter.width;
    }

    final textWidth = math.max(
      measure(q.senderName, senderStyle),
      measure(q.summary, summaryStyle),
    );
    final hasThumbnail =
        q.isAvailable &&
        q.preview != null &&
        const {
          MessageType.image,
        }.contains(q.preview!.kind);
    return 11 + textWidth + (hasThumbnail ? 46 : 0);
  }

  Widget _footer(
    BuildContext context,
    Color fg, {
    bool inline = false,
    bool forceForeground = false,
  }) {
    final faint = context.isDark
        ? const Color(0x80FFFFFF)
        : fg.withValues(alpha: 0.7);
    // Telegram Night 的 outgoing check 使用白色，pending activity 使用 50% 白；
    // Light 继续保持项目原有的已发送 / 已读明度关系。
    final statusColor = context.isDark
        ? (message.status == MessageStatus.sending
              ? faint
              : const Color(0xFFFFFFFF))
        : (message.status == MessageStatus.read ? fg : faint);
    return Padding(
      padding: inline ? EdgeInsets.zero : const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            DateTimeUtil.messageTime(message.time),
            style: _footerTextStyle(
              context,
              fg,
              forceForeground: forceForeground,
            ),
          ),
          if (showMessageStatus &&
              message.isMine &&
              message.status != MessageStatus.failed &&
              message.status.icon != null) ...[
            const SizedBox(width: 3),
            if (message.status == MessageStatus.sending)
              SendingClockIndicator(color: statusColor, size: 14)
            else
              Semantics(
                label: message.status.name,
                child: Icon(message.status.icon, size: 14, color: statusColor),
              ),
          ],
        ],
      ),
    );
  }

  /// 计算 Telegram 末行元信息组的真实宽度。
  ///
  /// 元信息参与正文换行决策，不能用估算值；否则短文本会留下多余空白，
  /// 多行文本也无法稳定贴到末行右侧。这里的计算必须与 [_footer] 的
  /// 字号、状态图标尺寸和间距保持完全一致。
  double _footerWidth(BuildContext context, Color fg) {
    // Text 实际渲染时会合并 DefaultTextStyle；测量必须使用相同完整样式，
    // 否则 Material 默认字距会让时间的真实宽度比测量值大约多 1.25px。
    final resolvedStyle = DefaultTextStyle.of(
      context,
    ).style.merge(_footerTextStyle(context, fg));
    final painter = TextPainter(
      text: TextSpan(
        text: DateTimeUtil.messageTime(message.time),
        style: resolvedStyle,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();

    final showsStatus =
        showMessageStatus &&
        message.isMine &&
        message.status != MessageStatus.failed &&
        message.status.icon != null;
    return painter.width + (showsStatus ? 3 + 14 : 0);
  }

  TextStyle _footerTextStyle(
    BuildContext context,
    Color fg, {
    bool forceForeground = false,
  }) {
    if (forceForeground) {
      return AppTextStyles.telegramMessageMeta.copyWith(
        color: fg.withValues(alpha: 0.7),
      );
    }
    if (context.isDark) {
      return AppTextStyles.telegramMessageMeta.copyWith(
        color: const Color(0x80FFFFFF),
      );
    }
    final faint = fg.withValues(alpha: 0.7);
    return AppTextStyles.telegramMessageMeta.copyWith(
      color: message.isMine ? faint : context.colorScheme.onSurfaceVariant,
    );
  }
}

/// 富消息引用的 40px 左侧预览；加载失败时保留类型图标。
class _ReplyThumbnail extends StatelessWidget {
  const _ReplyThumbnail({required this.preview, required this.color});

  final ReplyPreview preview;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = preview.previewUrl;
    final fallback = SvgPicture.asset(
      _replyPreviewIconAsset(preview.kind),
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(
        color.withValues(alpha: 0.75),
        BlendMode.srcIn,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.square(
        dimension: 40,
        child: url == null || url.isEmpty
            ? ColoredBox(
                color: color.withValues(alpha: 0.10),
                child: Center(child: fallback),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: fallback),
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : ColoredBox(
                        color: color.withValues(alpha: 0.10),
                        child: Center(child: fallback),
                      ),
              ),
      ),
    );
  }

  String _replyPreviewIconAsset(MessageType type) => switch (type) {
    MessageType.image => 'assets/icons/chat/image.svg',
    MessageType.file => 'assets/icons/chat/file.svg',
    MessageType.text ||
    MessageType.recall ||
    MessageType.system => 'assets/icons/chat/message_bubble.svg',
  };
}

/// 群聊气泡左侧小头像
class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: AppSizes.avatarSm / 2,
      backgroundColor: ColorUtil.fromText(name),
      child: Text(
        name.isEmpty ? '?' : name.characters.last,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 会话列表项组件。
///
/// 使用会话列表语义 token，Light / Dark 共用同一套几何与排版节奏；
/// 主题只改变颜色、表面和状态反馈，不再通过主题切换列表密度。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_time_util.dart';
import '../../../data/enums/message_type.dart';
import '../../../data/models/conversation_model.dart';
import '../../../shared/widgets/avatar/app_avatar.dart';
import '../../../shared/widgets/badge/app_badge.dart';

class ConversationItem extends StatelessWidget {
  const ConversationItem({
    super.key,
    required this.conversation,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showDivider = false,
    this.previewMaxLines = 1,
  });

  final ConversationModel conversation;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool showDivider;
  final int previewMaxLines;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final list = context.conversationTokens;
    final dividerWidth = 1 / MediaQuery.devicePixelRatioOf(context);
    // Pinned is a structural state, not a selection state. Keep normal rows on
    // one surface and communicate pinning in the trailing metadata instead of
    // tinting the whole conversation row.
    final backgroundColor = selected
        ? list.selectedBackground
        : list.background;
    final separatorInset =
        AppSizes.paddingLg + list.avatarSize + AppSizes.paddingItem;

    // Conversation rows are intentionally density-stable. Android vendors may
    // expose very different system text/display scaling; clamping only this
    // dense navigation surface keeps the list rhythm consistent without
    // disabling accessibility scaling across the rest of the app.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        curve: AppConstants.motionStandard,
        height: previewMaxLines > 1
            ? list.itemMinHeight + 20
            : list.itemMinHeight,
        color: backgroundColor,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return list.pressedBackground;
              }
              return Colors.transparent;
            }),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.paddingLg,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AppAvatar(
                            imageUrl: c.avatarUrl,
                            name: c.title,
                            size: list.avatarSize,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: AnimatedSwitcher(
                              duration: AppConstants.animFast,
                              reverseDuration: AppConstants.animInstant,
                              switchInCurve: AppConstants.motionStandard,
                              switchOutCurve: AppConstants.motionExit,
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                              child: selected
                                  ? Container(
                                      key: const ValueKey('selected'),
                                      width: 21,
                                      height: 21,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: context.isDark
                                            ? Colors.white
                                            : context.semanticColors.accent,
                                        border: Border.all(
                                          color: backgroundColor,
                                          width: dividerWidth,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        size: 15,
                                        color: context.isDark
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('unselected'),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSizes.paddingItem),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _titleRow(context),
                                  const SizedBox(height: 2),
                                  _previewRow(context),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSizes.paddingSm),
                            _trailingColumn(context),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showDivider)
                  PositionedDirectional(
                    start: separatorInset,
                    end: AppSizes.paddingLg,
                    bottom: 0,
                    child: SizedBox(
                      height: dividerWidth,
                      child: ColoredBox(color: list.separator),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleRow(BuildContext context) {
    final c = conversation;
    final list = context.conversationTokens;
    return Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            c.title,
            strutStyle: const StrutStyle(
              fontSize: 16,
              height: 22 / 16,
              forceStrutHeight: true,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.listPrimary.copyWith(
              color: list.title,
              // 会话名始终是列表第一视觉层级；未读状态交给时间与角标表达，
              // 避免已读会话名称退化成与消息预览相同的正文权重。
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (c.isMuted) ...[
          const SizedBox(width: 6),
          SvgPicture.asset(
            'assets/icons/chat/mute.svg',
            width: 15,
            height: 15,
            colorFilter: ColorFilter.mode(list.secondary, BlendMode.srcIn),
            semanticsLabel: '免打扰',
          ),
        ],
      ],
    );
  }

  Widget _previewRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            _previewSpan(context),
            strutStyle: const StrutStyle(
              fontSize: 13,
              height: 18 / 13,
              forceStrutHeight: true,
            ),
            maxLines: previewMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _trailingColumn(BuildContext context) {
    final c = conversation;
    final list = context.conversationTokens;
    return SizedBox(
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateTimeUtil.conversationTime(c.time),
            strutStyle: const StrutStyle(
              fontSize: 12.5,
              height: 16 / 12.5,
              forceStrutHeight: true,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTextStyles.conversationTime.copyWith(
              color: c.hasUnread ? list.unreadTime : list.time,
              fontWeight: c.hasUnread ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: AppSizes.paddingSm),
          SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.centerRight,
              child: c.hasUnread
                  ? AppBadge(count: c.unreadCount, muted: c.isMuted)
                  : c.isPinned
                  ? SvgPicture.asset(
                      'assets/icons/chat/pin.svg',
                      width: 14,
                      height: 14,
                      colorFilter: ColorFilter.mode(
                        list.secondary,
                        BlendMode.srcIn,
                      ),
                      semanticsLabel: '已置顶',
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _previewSpan(BuildContext context) {
    final c = conversation;
    final list = context.conversationTokens;
    // 最后一条消息属于辅助信息，使用 metadata 字阶与会话名形成明确主次。
    final previewStyle = AppTextStyles.metadata;
    final secondaryTextColor = list.secondary;
    final functionalAccent = list.unreadTime;
    final spans = <InlineSpan>[];

    final reply = c.lastReply;
    if (reply != null) {
      final sender = reply.senderName.trim();
      final summary = reply.summary.trim();
      spans.add(
        TextSpan(
          text: sender.isEmpty ? '回复 $summary · ' : '回复 $sender：$summary · ',
          style: previewStyle.copyWith(color: secondaryTextColor),
        ),
      );
    }

    if (c.isMediaPreview) {
      final iconAsset = _previewIconAsset(c.lastMessageType);
      if (iconAsset != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSizes.paddingXs),
              child: SvgPicture.asset(
                iconAsset,
                width: 15,
                height: 15,
                colorFilter: ColorFilter.mode(
                  functionalAccent,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: c.lastMessageType.previewLabel,
          style: previewStyle.copyWith(color: secondaryTextColor),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: c.lastMessageText,
          style: previewStyle.copyWith(color: secondaryTextColor),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  String? _previewIconAsset(MessageType type) => switch (type) {
    MessageType.image => 'assets/icons/chat/image.svg',
    MessageType.file => 'assets/icons/chat/file.svg',
    MessageType.text || MessageType.recall || MessageType.system => null,
  };
}

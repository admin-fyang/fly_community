/// flutter_chat_ui 与项目设计系统之间的视觉适配层。
///
/// 第三方库只负责消息列表、分组、动画和滚动内核；颜色、字阶、圆角与消息
/// 最大宽度必须来自项目 DESIGN token，禁止页面直接使用库的示例默认主题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as flyer;

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';

/// Pure presentation grouping state for Telegram-style connected bubbles.
///
/// Derived from flutter_chat_core's MessageGroupStatus and never persisted.
enum BubbleGroupPosition { single, first, middle, last }

/// 将 Restrained Messenger token 映射为 flutter_chat_ui 主题。
class ChatUiDesignAdapter {
  ChatUiDesignAdapter._();

  /// 构建随 Light / Dark 自动切换的第三方聊天主题。
  static flyer.ChatTheme themeOf(BuildContext context) {
    final colors = context.colorScheme;
    final bubbles = context.chatBubbleTokens;
    final wallpaper = context.chatWallpaperTokens;
    return flyer.ChatTheme(
      colors: flyer.ChatColors(
        primary: bubbles.outgoingEnd,
        onPrimary: bubbles.textOutgoing,
        surface: wallpaper.base,
        onSurface: bubbles.textIncoming,
        surfaceContainer: bubbles.incomingFill,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainerHigh: colors.surfaceContainerHigh,
      ),
      typography: flyer.ChatTypography(
        bodyLarge: AppTextStyles.messageBody,
        bodyMedium: AppTextStyles.messageBody,
        bodySmall: AppTextStyles.metadata,
        labelLarge: AppTextStyles.buttonLabel,
        labelMedium: AppTextStyles.metadata.copyWith(
          fontWeight: FontWeight.w500,
        ),
        // 时间与状态是辅助信息，不能继承角标的强调字重。
        labelSmall: AppTextStyles.badgeLabel.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
      // 仅作为不支持方向性圆角的第三方消息回退值；文本、图片和业务气泡
      // 使用 [bubbleRadius] 保留 Telegram 式小尾角。
      shape: const BorderRadius.all(
        Radius.circular(AppSizes.radiusBubble),
      ),
    );
  }

  /// Convert Flyer Chat grouping metadata into a presentation-only state.
  static BubbleGroupPosition groupPositionOf(
    flyer.MessageGroupStatus? status,
  ) {
    if (status == null || (status.isFirst && status.isLast)) {
      return BubbleGroupPosition.single;
    }
    if (status.isFirst) return BubbleGroupPosition.first;
    if (status.isLast) return BubbleGroupPosition.last;
    return BubbleGroupPosition.middle;
  }

  /// Telegram-inspired connected bubble geometry.
  ///
  /// Only the sender-side corners tighten within a group. The outer side stays
  /// round and only the last bubble receives the small tail corner.
  static BorderRadius bubbleRadius({
    required bool isSentByMe,
    BubbleGroupPosition groupPosition = BubbleGroupPosition.single,
  }) {
    const main = Radius.circular(AppSizes.radiusBubble);
    const connected = Radius.circular(7);
    const tail = Radius.circular(AppSizes.radiusBubbleTail);

    if (isSentByMe) {
      return switch (groupPosition) {
        BubbleGroupPosition.single => const BorderRadius.only(
          topLeft: main,
          topRight: main,
          bottomLeft: main,
          bottomRight: tail,
        ),
        BubbleGroupPosition.first => const BorderRadius.only(
          topLeft: main,
          topRight: main,
          bottomLeft: main,
          bottomRight: connected,
        ),
        BubbleGroupPosition.middle => const BorderRadius.only(
          topLeft: main,
          topRight: connected,
          bottomLeft: main,
          bottomRight: connected,
        ),
        BubbleGroupPosition.last => const BorderRadius.only(
          topLeft: main,
          topRight: connected,
          bottomLeft: main,
          bottomRight: tail,
        ),
      };
    }

    return switch (groupPosition) {
      BubbleGroupPosition.single => const BorderRadius.only(
        topLeft: main,
        topRight: main,
        bottomLeft: tail,
        bottomRight: main,
      ),
      BubbleGroupPosition.first => const BorderRadius.only(
        topLeft: main,
        topRight: main,
        bottomLeft: connected,
        bottomRight: main,
      ),
      BubbleGroupPosition.middle => const BorderRadius.only(
        topLeft: connected,
        topRight: main,
        bottomLeft: connected,
        bottomRight: main,
      ),
      BubbleGroupPosition.last => const BorderRadius.only(
        topLeft: connected,
        topRight: main,
        bottomLeft: tail,
        bottomRight: main,
      ),
    };
  }

  /// Slightly narrower messages create the side breathing room typical of
  /// Telegram while preserving the existing responsive layout.
  static BoxConstraints messageConstraints(BuildContext context) =>
      BoxConstraints(maxWidth: context.screenSize.width * 0.82);

  /// 非文字消息降低视觉占比，让图片、视频和业务卡片不会压过聊天正文。
  static BoxConstraints nonTextMessageConstraints(BuildContext context) =>
      BoxConstraints(
        maxWidth:
            context.screenSize.width * AppSizes.nonTextMessageMaxWidthFactor,
      );
}

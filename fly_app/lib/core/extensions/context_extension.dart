/// BuildContext 主题快捷扩展。
///
/// 让组件以 `context.colorScheme` / `context.tokens` / `context.isDark` 等形式
/// 直接读取主题,避免反复书写 Theme.of(context)。
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_semantic_colors.dart';
import '../theme/chat_bubble_tokens.dart';
import '../theme/chat_input_tokens.dart';
import '../theme/chat_wallpaper_tokens.dart';
import '../theme/conversation_list_tokens.dart';
import '../theme/overlay_tokens.dart';

/// BuildContext 快捷访问主题，避免组件里反复写 Theme.of(context)
///
/// 注意：`theme` / `textTheme` 已由 GetX 的 context 扩展提供，这里不再重复定义，
/// 以免产生 ambiguous_extension_member_access。组件需要 textTheme 时直接用
/// `context.textTheme`（来自 GetX），需要语义色用下面的 `colorScheme` / `tokens`。
extension ContextThemeX on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// IM 专有语义色（气泡、未读、在线状态等），随主题自动切换
  AppColorTokens get tokens => Theme.of(this).extension<AppColorTokens>()!;

  /// App-wide semantic surface/text roles.
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;

  /// Conversation-list-specific visual roles.
  ConversationListTokens get conversationTokens =>
      Theme.of(this).extension<ConversationListTokens>()!;

  /// Message bubble presentation roles.
  ChatBubbleTokens get chatBubbleTokens =>
      Theme.of(this).extension<ChatBubbleTokens>()!;

  /// Chat composer/input presentation roles.
  ChatInputTokens get chatInputTokens =>
      Theme.of(this).extension<ChatInputTokens>()!;

  /// Chat wallpaper treatment roles.
  ChatWallpaperTokens get chatWallpaperTokens =>
      Theme.of(this).extension<ChatWallpaperTokens>()!;

  /// Context-menu / action-sheet visual roles.
  OverlayTokens get overlayTokens => Theme.of(this).extension<OverlayTokens>()!;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Size get screenSize => MediaQuery.sizeOf(this);

  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
}

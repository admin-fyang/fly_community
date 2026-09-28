/// Semantic colors and geometry for the conversation list.
library;

import 'package:flutter/material.dart';

@immutable
class ConversationListTokens extends ThemeExtension<ConversationListTokens> {
  const ConversationListTokens({
    required this.background,
    required this.pinnedBackground,
    required this.pressedBackground,
    required this.selectedBackground,
    required this.separator,
    required this.title,
    required this.secondary,
    required this.time,
    required this.unreadTime,
    required this.badge,
    required this.badgeText,
    required this.mutedBadge,
    required this.mutedBadgeText,
    required this.avatarSize,
    required this.itemMinHeight,
  });

  final Color background;
  final Color pinnedBackground;
  final Color pressedBackground;
  final Color selectedBackground;
  final Color separator;
  final Color title;
  final Color secondary;
  final Color time;
  final Color unreadTime;
  final Color badge;
  final Color badgeText;
  final Color mutedBadge;
  final Color mutedBadgeText;
  final double avatarSize;
  final double itemMinHeight;

  static const light = ConversationListTokens(
    background: Color(0xFFFFFFFF),
    pinnedBackground: Color(0xFFF7FAFC),
    pressedBackground: Color(0xFFEEF4F7),
    selectedBackground: Color(0xFFE7F4FB),
    separator: Color(0xFFEDF1F4),
    title: Color(0xFF17212B),
    secondary: Color(0xFF708499),
    time: Color(0xFF8293A3),
    unreadTime: Color(0xFF24A1DE),
    badge: Color(0xFF24A1DE),
    badgeText: Color(0xFFFFFFFF),
    mutedBadge: Color(0xFFDFE3E8),
    mutedBadgeText: Color(0xFF708499),
    avatarSize: 48,
    itemMinHeight: 72,
  );

  // Blue-black preview: preserve Telegram ChatList contrast relationships,
  // while applying the product's custom cool-blue dark material.
  static const dark = ConversationListTokens(
    background: Color(0xFF05080D),
    pinnedBackground: Color(0xFF111820),
    pressedBackground: Color(0xFF0E151D),
    selectedBackground: Color(0xFF151E28),
    separator: Color(0x8C344353),
    title: Color(0xFFF7F9FC),
    secondary: Color(0xFF8795A4),
    time: Color(0xFF8795A4),
    unreadTime: Color(0xFF8795A4),
    badge: Color(0xFFFFFFFF),
    badgeText: Color(0xFF000000),
    mutedBadge: Color(0xFF666666),
    mutedBadgeText: Color(0xFF000000),
    avatarSize: 48,
    itemMinHeight: 72,
  );

  @override
  ConversationListTokens copyWith({
    Color? background,
    Color? pinnedBackground,
    Color? pressedBackground,
    Color? selectedBackground,
    Color? separator,
    Color? title,
    Color? secondary,
    Color? time,
    Color? unreadTime,
    Color? badge,
    Color? badgeText,
    Color? mutedBadge,
    Color? mutedBadgeText,
    double? avatarSize,
    double? itemMinHeight,
  }) {
    return ConversationListTokens(
      background: background ?? this.background,
      pinnedBackground: pinnedBackground ?? this.pinnedBackground,
      pressedBackground: pressedBackground ?? this.pressedBackground,
      selectedBackground: selectedBackground ?? this.selectedBackground,
      separator: separator ?? this.separator,
      title: title ?? this.title,
      secondary: secondary ?? this.secondary,
      time: time ?? this.time,
      unreadTime: unreadTime ?? this.unreadTime,
      badge: badge ?? this.badge,
      badgeText: badgeText ?? this.badgeText,
      mutedBadge: mutedBadge ?? this.mutedBadge,
      mutedBadgeText: mutedBadgeText ?? this.mutedBadgeText,
      avatarSize: avatarSize ?? this.avatarSize,
      itemMinHeight: itemMinHeight ?? this.itemMinHeight,
    );
  }

  @override
  ConversationListTokens lerp(
    ThemeExtension<ConversationListTokens>? other,
    double t,
  ) {
    if (other is! ConversationListTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ConversationListTokens(
      background: c(background, other.background),
      pinnedBackground: c(pinnedBackground, other.pinnedBackground),
      pressedBackground: c(pressedBackground, other.pressedBackground),
      selectedBackground: c(selectedBackground, other.selectedBackground),
      separator: c(separator, other.separator),
      title: c(title, other.title),
      secondary: c(secondary, other.secondary),
      time: c(time, other.time),
      unreadTime: c(unreadTime, other.unreadTime),
      badge: c(badge, other.badge),
      badgeText: c(badgeText, other.badgeText),
      mutedBadge: c(mutedBadge, other.mutedBadge),
      mutedBadgeText: c(mutedBadgeText, other.mutedBadgeText),
      avatarSize: avatarSize + (other.avatarSize - avatarSize) * t,
      itemMinHeight: itemMinHeight + (other.itemMinHeight - itemMinHeight) * t,
    );
  }
}

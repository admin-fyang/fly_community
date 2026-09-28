/// Semantic presentation tokens for message bubbles.
library;

import 'package:flutter/material.dart';

@immutable
class ChatBubbleTokens extends ThemeExtension<ChatBubbleTokens> {
  const ChatBubbleTokens({
    required this.incomingFill,
    required this.incomingPressed,
    required this.incomingStroke,
    required this.outgoingStart,
    required this.outgoingEnd,
    required this.outgoingPressed,
    required this.textIncoming,
    required this.textOutgoing,
    required this.cardFill,
    required this.cardStroke,
    required this.mediaMetaOverlay,
    required this.replyFill,
    required this.replyAccent,
    required this.selectedOverlay,
    required this.reactionInactive,
    required this.reactionActive,
  });

  final Color incomingFill;
  final Color incomingPressed;
  final Color incomingStroke;
  final Color outgoingStart;
  final Color outgoingEnd;
  final Color outgoingPressed;
  final Color textIncoming;
  final Color textOutgoing;
  final Color cardFill;
  final Color cardStroke;
  final Color mediaMetaOverlay;
  final Color replyFill;
  final Color replyAccent;
  final Color selectedOverlay;
  final Color reactionInactive;
  final Color reactionActive;

  static const light = ChatBubbleTokens(
    incomingFill: Color(0xFFFEFFFF),
    incomingPressed: Color(0xFFF3F7F9),
    incomingStroke: Color(0x66CBD7DD),
    outgoingStart: Color(0xFF4FB6F6),
    outgoingEnd: Color(0xFF7559E8),
    outgoingPressed: Color(0xFF6D4CD6),
    textIncoming: Color(0xFF17212B),
    textOutgoing: Color(0xFFFFFFFF),
    cardFill: Color(0xFFFFFFFF),
    cardStroke: Color(0xFFD8E1E6),
    mediaMetaOverlay: Color(0x94000000),
    replyFill: Color(0x1A24A1DE),
    replyAccent: Color(0xFF24A1DE),
    selectedOverlay: Color(0x2424A1DE),
    reactionInactive: Color(0x1824A1DE),
    reactionActive: Color(0xFF24A1DE),
  );

  // Blue-black preview: keep Telegram Night's message-layer contrast but
  // apply the product's custom cool-blue material hue.
  static const dark = ChatBubbleTokens(
    incomingFill: Color(0xE6121A22),
    incomingPressed: Color(0x59FFFFFF),
    incomingStroke: Color(0x00000000),
    outgoingStart: Color(0xFF48AEF2),
    outgoingEnd: Color(0xFF7057E8),
    outgoingPressed: Color(0xFF6547DA),
    textIncoming: Color(0xFFFFFFFF),
    textOutgoing: Color(0xFFFFFFFF),
    cardFill: Color(0xFF151E27),
    cardStroke: Color(0xFF151E27),
    mediaMetaOverlay: Color(0x99000000),
    replyFill: Color(0x1FFFFFFF),
    replyAccent: Color(0xFFFFFFFF),
    selectedOverlay: Color(0x33FFFFFF),
    reactionInactive: Color(0x12FFFFFF),
    reactionActive: Color(0xFFFFFFFF),
  );

  @override
  ChatBubbleTokens copyWith({
    Color? incomingFill,
    Color? incomingPressed,
    Color? incomingStroke,
    Color? outgoingStart,
    Color? outgoingEnd,
    Color? outgoingPressed,
    Color? textIncoming,
    Color? textOutgoing,
    Color? cardFill,
    Color? cardStroke,
    Color? mediaMetaOverlay,
    Color? replyFill,
    Color? replyAccent,
    Color? selectedOverlay,
    Color? reactionInactive,
    Color? reactionActive,
  }) {
    return ChatBubbleTokens(
      incomingFill: incomingFill ?? this.incomingFill,
      incomingPressed: incomingPressed ?? this.incomingPressed,
      incomingStroke: incomingStroke ?? this.incomingStroke,
      outgoingStart: outgoingStart ?? this.outgoingStart,
      outgoingEnd: outgoingEnd ?? this.outgoingEnd,
      outgoingPressed: outgoingPressed ?? this.outgoingPressed,
      textIncoming: textIncoming ?? this.textIncoming,
      textOutgoing: textOutgoing ?? this.textOutgoing,
      cardFill: cardFill ?? this.cardFill,
      cardStroke: cardStroke ?? this.cardStroke,
      mediaMetaOverlay: mediaMetaOverlay ?? this.mediaMetaOverlay,
      replyFill: replyFill ?? this.replyFill,
      replyAccent: replyAccent ?? this.replyAccent,
      selectedOverlay: selectedOverlay ?? this.selectedOverlay,
      reactionInactive: reactionInactive ?? this.reactionInactive,
      reactionActive: reactionActive ?? this.reactionActive,
    );
  }

  @override
  ChatBubbleTokens lerp(
    ThemeExtension<ChatBubbleTokens>? other,
    double t,
  ) {
    if (other is! ChatBubbleTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChatBubbleTokens(
      incomingFill: c(incomingFill, other.incomingFill),
      incomingPressed: c(incomingPressed, other.incomingPressed),
      incomingStroke: c(incomingStroke, other.incomingStroke),
      outgoingStart: c(outgoingStart, other.outgoingStart),
      outgoingEnd: c(outgoingEnd, other.outgoingEnd),
      outgoingPressed: c(outgoingPressed, other.outgoingPressed),
      textIncoming: c(textIncoming, other.textIncoming),
      textOutgoing: c(textOutgoing, other.textOutgoing),
      cardFill: c(cardFill, other.cardFill),
      cardStroke: c(cardStroke, other.cardStroke),
      mediaMetaOverlay: c(mediaMetaOverlay, other.mediaMetaOverlay),
      replyFill: c(replyFill, other.replyFill),
      replyAccent: c(replyAccent, other.replyAccent),
      selectedOverlay: c(selectedOverlay, other.selectedOverlay),
      reactionInactive: c(reactionInactive, other.reactionInactive),
      reactionActive: c(reactionActive, other.reactionActive),
    );
  }
}

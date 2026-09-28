/// Semantic presentation tokens for the chat composer/input panel.
library;

import 'package:flutter/material.dart';

@immutable
class ChatInputTokens extends ThemeExtension<ChatInputTokens> {
  const ChatInputTokens({
    required this.panelBackground,
    required this.inputBackground,
    required this.inputBorder,
    required this.text,
    required this.placeholder,
    required this.control,
    required this.controlDisabled,
    required this.accent,
    required this.destructive,
    required this.recordingFill,
  });

  final Color panelBackground;
  final Color inputBackground;
  final Color inputBorder;
  final Color text;
  final Color placeholder;
  final Color control;
  final Color controlDisabled;
  final Color accent;
  final Color destructive;
  final Color recordingFill;

  static const light = ChatInputTokens(
    panelBackground: Color(0xF0FFFFFF),
    inputBackground: Color(0xFFF2F2F7),
    inputBorder: Color(0x1A000000),
    text: Color(0xFF17212B),
    placeholder: Color(0xFF8E8E93),
    control: Color(0xFF6D6D72),
    controlDisabled: Color(0xFFB8C2CA),
    accent: Color(0xFF24A1DE),
    destructive: Color(0xFFFF3B30),
    recordingFill: Color(0x14FF3B30),
  );

  static const dark = ChatInputTokens(
    panelBackground: Color(0xE61C1C1E),
    inputBackground: Color(0xFF262628),
    inputBorder: Color(0x24FFFFFF),
    text: Color(0xFFFFFFFF),
    placeholder: Color(0xFF8E8E93),
    control: Color(0xFFAEAEB2),
    controlDisabled: Color(0xFF5B5B60),
    accent: Color(0xFF74C7F2),
    destructive: Color(0xFFEB5545),
    recordingFill: Color(0x24EB5545),
  );

  @override
  ChatInputTokens copyWith({
    Color? panelBackground,
    Color? inputBackground,
    Color? inputBorder,
    Color? text,
    Color? placeholder,
    Color? control,
    Color? controlDisabled,
    Color? accent,
    Color? destructive,
    Color? recordingFill,
  }) {
    return ChatInputTokens(
      panelBackground: panelBackground ?? this.panelBackground,
      inputBackground: inputBackground ?? this.inputBackground,
      inputBorder: inputBorder ?? this.inputBorder,
      text: text ?? this.text,
      placeholder: placeholder ?? this.placeholder,
      control: control ?? this.control,
      controlDisabled: controlDisabled ?? this.controlDisabled,
      accent: accent ?? this.accent,
      destructive: destructive ?? this.destructive,
      recordingFill: recordingFill ?? this.recordingFill,
    );
  }

  @override
  ChatInputTokens lerp(
    ThemeExtension<ChatInputTokens>? other,
    double t,
  ) {
    if (other is! ChatInputTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChatInputTokens(
      panelBackground: c(panelBackground, other.panelBackground),
      inputBackground: c(inputBackground, other.inputBackground),
      inputBorder: c(inputBorder, other.inputBorder),
      text: c(text, other.text),
      placeholder: c(placeholder, other.placeholder),
      control: c(control, other.control),
      controlDisabled: c(controlDisabled, other.controlDisabled),
      accent: c(accent, other.accent),
      destructive: c(destructive, other.destructive),
      recordingFill: c(recordingFill, other.recordingFill),
    );
  }
}

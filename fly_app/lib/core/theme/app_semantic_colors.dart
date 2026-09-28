/// App-wide semantic colors inspired by Telegram-iOS's role-based theme model.
///
/// The palette deliberately keeps the product's own cool-neutral identity.
/// Telegram is used as a hierarchy/material reference, not as a literal color
/// sheet to copy into every Flutter screen.
library;

import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.backgroundPrimary,
    required this.backgroundGrouped,
    required this.surface,
    required this.surfaceElevated,
    required this.surfacePressed,
    required this.separator,
    required this.separatorStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.placeholder,
    required this.accent,
    required this.destructive,
    required this.success,
    required this.overlayDim,
  });

  final Color backgroundPrimary;
  final Color backgroundGrouped;
  final Color surface;
  final Color surfaceElevated;
  final Color surfacePressed;
  final Color separator;
  final Color separatorStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color placeholder;
  final Color accent;
  final Color destructive;
  final Color success;
  final Color overlayDim;

  /// 浅色模式使用 Telegram iOS 风格的中性分组背景与纯白表面，
  /// 通过背景、表面和分隔线的明度层级区分内容，不依赖卡片阴影。
  static const light = AppSemanticColors(
    backgroundPrimary: Color(0xFFFFFFFF),
    backgroundGrouped: Color(0xFFEFEFF4),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF8FAFB),
    surfacePressed: Color(0xFFE5E5EA),
    separator: Color(0xFFC8C7CC),
    separatorStrong: Color(0xFFD5DEE5),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF8E8E93),
    textTertiary: Color(0xFFBAB9BE),
    textDisabled: Color(0xFFB4BEC7),
    placeholder: Color(0xFF9AA8B4),
    accent: Color(0xFF24A1DE),
    destructive: Color(0xFFFF3B30),
    success: Color(0xFF3FCB70),
    overlayDim: Color(0x57000000),
  );

  /// Dark blue-black preview keeps Telegram-iOS Night's luminance hierarchy but
  /// shifts neutral blacks toward a restrained cool-blue hue. These custom values
  /// are product colors, not literal Telegram Night color constants.
  static const dark = AppSemanticColors(
    backgroundPrimary: Color(0xFF05080D),
    backgroundGrouped: Color(0xFF05080D),
    surface: Color(0xFF111820),
    surfaceElevated: Color(0xFF202A35),
    surfacePressed: Color(0xFF283442),
    separator: Color(0x8C344353),
    separatorStrong: Color(0x99526476),
    textPrimary: Color(0xFFF7F9FC),
    textSecondary: Color(0xFF98A5B3),
    textTertiary: Color(0xFF7E8B99),
    textDisabled: Color(0xFF6C7885),
    placeholder: Color(0xFF8996A4),
    accent: Color(0xFF64C2EE),
    destructive: Color(0xFFEB5545),
    success: Color(0xFF45D47A),
    overlayDim: Color(0xA6000000),
  );

  @override
  AppSemanticColors copyWith({
    Color? backgroundPrimary,
    Color? backgroundGrouped,
    Color? surface,
    Color? surfaceElevated,
    Color? surfacePressed,
    Color? separator,
    Color? separatorStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? placeholder,
    Color? accent,
    Color? destructive,
    Color? success,
    Color? overlayDim,
  }) {
    return AppSemanticColors(
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundGrouped: backgroundGrouped ?? this.backgroundGrouped,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      separator: separator ?? this.separator,
      separatorStrong: separatorStrong ?? this.separatorStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      placeholder: placeholder ?? this.placeholder,
      accent: accent ?? this.accent,
      destructive: destructive ?? this.destructive,
      success: success ?? this.success,
      overlayDim: overlayDim ?? this.overlayDim,
    );
  }

  @override
  AppSemanticColors lerp(
    ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemanticColors(
      backgroundPrimary: c(backgroundPrimary, other.backgroundPrimary),
      backgroundGrouped: c(backgroundGrouped, other.backgroundGrouped),
      surface: c(surface, other.surface),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfacePressed: c(surfacePressed, other.surfacePressed),
      separator: c(separator, other.separator),
      separatorStrong: c(separatorStrong, other.separatorStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textDisabled: c(textDisabled, other.textDisabled),
      placeholder: c(placeholder, other.placeholder),
      accent: c(accent, other.accent),
      destructive: c(destructive, other.destructive),
      success: c(success, other.success),
      overlayDim: c(overlayDim, other.overlayDim),
    );
  }
}

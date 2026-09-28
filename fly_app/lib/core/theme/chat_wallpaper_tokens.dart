/// Semantic treatment for chat wallpapers.
///
/// Telegram treats wallpaper as an environment layer whose intensity can be
/// controlled independently from message bubbles. The app follows that model:
/// a muted base, a low-contrast pattern and a soft veil keep message content in
/// the foreground.
library;

import 'package:flutter/material.dart';

@immutable
class ChatWallpaperTokens extends ThemeExtension<ChatWallpaperTokens> {
  const ChatWallpaperTokens({
    required this.base,
    required this.patternTint,
    required this.patternOpacity,
    required this.rasterOpacity,
    required this.veilTop,
    required this.veilBottom,
  });

  final Color base;
  final Color patternTint;
  final double patternOpacity;
  final double rasterOpacity;
  final Color veilTop;
  final Color veilBottom;

  /// The light wallpaper intentionally sits several luminance steps below pure
  /// white. Incoming white bubbles therefore remain readable without shadows.
  static const light = ChatWallpaperTokens(
    base: Color(0xFFE3ECEF),
    patternTint: Color(0xFF78929C),
    patternOpacity: 0.35,
    rasterOpacity: 0.075,
    veilTop: Color(0x18FFFFFF),
    veilBottom: Color(0x0FFFFFFF),
  );

  static const dark = ChatWallpaperTokens(
    base: Color(0xFF0C141A),
    patternTint: Color(0xFF84949C),
    patternOpacity: 0.055,
    rasterOpacity: 0.05,
    veilTop: Color(0x0A000000),
    veilBottom: Color(0x2B000000),
  );

  @override
  ChatWallpaperTokens copyWith({
    Color? base,
    Color? patternTint,
    double? patternOpacity,
    double? rasterOpacity,
    Color? veilTop,
    Color? veilBottom,
  }) {
    return ChatWallpaperTokens(
      base: base ?? this.base,
      patternTint: patternTint ?? this.patternTint,
      patternOpacity: patternOpacity ?? this.patternOpacity,
      rasterOpacity: rasterOpacity ?? this.rasterOpacity,
      veilTop: veilTop ?? this.veilTop,
      veilBottom: veilBottom ?? this.veilBottom,
    );
  }

  @override
  ChatWallpaperTokens lerp(
    ThemeExtension<ChatWallpaperTokens>? other,
    double t,
  ) {
    if (other is! ChatWallpaperTokens) return this;
    return ChatWallpaperTokens(
      base: Color.lerp(base, other.base, t)!,
      patternTint: Color.lerp(patternTint, other.patternTint, t)!,
      patternOpacity:
          patternOpacity + (other.patternOpacity - patternOpacity) * t,
      rasterOpacity: rasterOpacity + (other.rasterOpacity - rasterOpacity) * t,
      veilTop: Color.lerp(veilTop, other.veilTop, t)!,
      veilBottom: Color.lerp(veilBottom, other.veilBottom, t)!,
    );
  }
}

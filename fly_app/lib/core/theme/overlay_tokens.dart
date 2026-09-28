/// Semantic colors for context menus, action sheets and lightweight overlays.
library;

import 'package:flutter/material.dart';

@immutable
class OverlayTokens extends ThemeExtension<OverlayTokens> {
  const OverlayTokens({
    required this.dim,
    required this.panel,
    required this.separator,
    required this.itemHighlighted,
    required this.primaryText,
    required this.secondaryText,
    required this.destructive,
  });

  final Color dim;
  final Color panel;
  final Color separator;
  final Color itemHighlighted;
  final Color primaryText;
  final Color secondaryText;
  final Color destructive;

  static const light = OverlayTokens(
    dim: Color(0x52000000),
    panel: Color(0xF2FFFFFF),
    separator: Color(0x1A000000),
    itemHighlighted: Color(0x0D000000),
    primaryText: Color(0xFF17212B),
    secondaryText: Color(0xFF708499),
    destructive: Color(0xFFFF3B30),
  );

  static const dark = OverlayTokens(
    dim: Color(0xA6000000),
    panel: Color(0xE6252527),
    separator: Color(0x1FFFFFFF),
    itemHighlighted: Color(0x1FFFFFFF),
    primaryText: Color(0xFFF2F2F7),
    secondaryText: Color(0xFF8E8E93),
    destructive: Color(0xFFEB5545),
  );

  @override
  OverlayTokens copyWith({
    Color? dim,
    Color? panel,
    Color? separator,
    Color? itemHighlighted,
    Color? primaryText,
    Color? secondaryText,
    Color? destructive,
  }) {
    return OverlayTokens(
      dim: dim ?? this.dim,
      panel: panel ?? this.panel,
      separator: separator ?? this.separator,
      itemHighlighted: itemHighlighted ?? this.itemHighlighted,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      destructive: destructive ?? this.destructive,
    );
  }

  @override
  OverlayTokens lerp(ThemeExtension<OverlayTokens>? other, double t) {
    if (other is! OverlayTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return OverlayTokens(
      dim: c(dim, other.dim),
      panel: c(panel, other.panel),
      separator: c(separator, other.separator),
      itemHighlighted: c(itemHighlighted, other.itemHighlighted),
      primaryText: c(primaryText, other.primaryText),
      secondaryText: c(secondaryText, other.secondaryText),
      destructive: c(destructive, other.destructive),
    );
  }
}

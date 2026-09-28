/// Unified circular selection indicator for contact/member pickers.
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';

class AppSelectionIndicator extends StatelessWidget {
  const AppSelectionIndicator({
    super.key,
    required this.selected,
    this.size = 22,
  });

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final dark = context.isDark;
    final selectedFill = dark ? Colors.white : semantic.accent;
    final selectedForeground = dark ? Colors.black : Colors.white;
    final borderColor = selected
        ? selectedFill
        : dark
        ? Colors.white.withValues(alpha: 0.30)
        : semantic.separatorStrong;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? selectedFill : Colors.transparent,
        border: Border.all(
          color: borderColor,
          width: selected ? 1.5 : 1.25,
        ),
      ),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        scale: selected ? 1 : 0.72,
        child: Icon(
          Icons.check_rounded,
          size: size * 0.64,
          color: selectedForeground,
        ),
      ),
    );
  }
}

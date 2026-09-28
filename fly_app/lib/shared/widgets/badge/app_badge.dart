/// 未读计数角标组件。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.count, this.muted = false});

  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final list = context.conversationTokens;
    final bg = muted ? list.mutedBadge : list.badge;
    final fg = muted ? list.mutedBadgeText : list.badgeText;
    final text = count > 99 ? '99+' : '$count';
    final badgeWidth = switch (text.length) {
      1 => 20.0,
      2 => 24.0,
      _ => 32.0,
    };

    return SizedBox(
      width: badgeWidth,
      height: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
        child: Center(
          child: MediaQuery.withNoTextScaling(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: AppTextStyles.badgeLabel.copyWith(
                color: fg,
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

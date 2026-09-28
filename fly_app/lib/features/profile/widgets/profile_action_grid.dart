/// Profile quick-action grid.
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class ProfileAction {
  const ProfileAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Telegram-like action strip: one quiet grouped surface rather than four
/// independent mini cards. The visual hierarchy comes from spacing and press
/// feedback, not repeated borders/shadows.
class ProfileActionGrid extends StatelessWidget {
  const ProfileActionGrid({super.key, required this.actions});

  final List<ProfileAction> actions;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1.08,
      child: Material(
        color: semantic.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (final action in actions)
              Expanded(child: _cell(context, action)),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, ProfileAction action) {
    final semantic = context.semanticColors;
    return InkWell(
      onTap: action.onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return semantic.surfacePressed;
        }
        return Colors.transparent;
      }),
      child: SizedBox(
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: semantic.accent, size: 21),
            const SizedBox(height: 4),
            Text(
              action.label,
              maxLines: 1,
              style: AppTextStyles.metadata.copyWith(
                color: semantic.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

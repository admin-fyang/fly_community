/// Profile information row.
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (onTap != null && states.contains(WidgetState.pressed)) {
              return semantic.surfacePressed;
            }
            return Colors.transparent;
          }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.messageBody.copyWith(
                      color: semantic.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.metadata.copyWith(
                        color: semantic.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: semantic.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

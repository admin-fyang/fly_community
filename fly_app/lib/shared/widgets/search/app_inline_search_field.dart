/// Telegram-inspired inline search capsule for content pages.
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../interaction/app_pressable.dart';

class AppInlineSearchField extends StatelessWidget {
  const AppInlineSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 8),
    this.fillColor,
    this.borderColor,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;
  final EdgeInsetsGeometry margin;
  final Color? fillColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final fill = fillColor ??
        (context.isDark
            ? context.colorScheme.surfaceContainerHigh
            : semantic.surfacePressed.withValues(alpha: 0.72));

    return Padding(
      padding: margin,
      child: SizedBox(
        height: 36,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!, width: 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(
                Icons.search_rounded,
                size: 18,
                color: semantic.textTertiary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  cursorColor: semantic.accent,
                  cursorHeight: 18,
                  style: AppTextStyles.messageBody.copyWith(
                    color: semantic.textPrimary,
                    fontSize: 14.5,
                    height: 18 / 14.5,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintText: hint,
                    hintStyle: AppTextStyles.messageBody.copyWith(
                      color: semantic.placeholder,
                      fontSize: 14.5,
                      height: 18 / 14.5,
                    ),
                  ),
                ),
              ),
              if (controller != null) _clear(context, controller!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clear(BuildContext context, TextEditingController controller) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox(width: 10);
        return SizedBox(
          width: 34,
          height: 36,
          child: Center(
            child: ClipOval(
              child: AppPressable(
                semanticLabel: '清除搜索',
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                // Telegram-iOS Night list.inputClearButtonColor = #8B9197.
                // Light keeps the existing semantic role.
                normalColor: context.isDark
                    ? const Color(0xFF8B9197)
                    : context.semanticColors.textTertiary,
                pressedColor: context.semanticColors.textSecondary,
                scaleWhenPressed: 0.94,
                child: const SizedBox.square(
                  dimension: 16,
                  child: Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

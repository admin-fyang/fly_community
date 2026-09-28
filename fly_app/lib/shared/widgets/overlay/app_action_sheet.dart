/// Telegram/iOS-inspired lightweight action sheet.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../interaction/app_pressable.dart';

class _ActionSheetColors {
  const _ActionSheetColors({
    required this.dim,
    required this.panel,
    required this.separator,
    required this.itemHighlighted,
    required this.primaryText,
    required this.secondaryText,
    required this.destructive,
    required this.standardAction,
  });

  final Color dim;
  final Color panel;
  final Color separator;
  final Color itemHighlighted;
  final Color primaryText;
  final Color secondaryText;
  final Color destructive;
  final Color standardAction;

  static _ActionSheetColors of(BuildContext context) {
    final overlay = context.overlayTokens;
    if (!context.isDark) {
      return _ActionSheetColors(
        dim: overlay.dim,
        panel: overlay.panel,
        separator: overlay.separator,
        itemHighlighted: overlay.itemHighlighted,
        primaryText: overlay.primaryText,
        secondaryText: overlay.secondaryText,
        destructive: overlay.destructive,
        standardAction: context.semanticColors.accent,
      );
    }

    // Telegram-iOS / DefaultDarkPresentationTheme.swift /
    // PresentationThemeActionSheet. Keep this palette local to ActionSheet:
    // ContextMenu intentionally uses a different dark material.
    return const _ActionSheetColors(
      dim: Color(0x80000000),
      panel: Color(0xCC1C1C1D),
      separator: Color(0x8C545458),
      itemHighlighted: Color(0x80000000),
      primaryText: Color(0xFFFFFFFF),
      secondaryText: Color(0xFF5E5E5E),
      destructive: Color(0xFFEB5545),
      standardAction: Color(0xFFFFFFFF),
    );
  }
}

class AppActionSheetItem<T> {
  const AppActionSheetItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailingText,
    this.selected = false,
    this.destructive = false,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? trailingText;
  final bool selected;
  final bool destructive;
}

Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<AppActionSheetItem<T>> items,
  String cancelText = '取消',
  bool showCancel = true,
  double maxHeightFactor = 0.72,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: _ActionSheetColors.of(context).dim,
    elevation: 0,
    useSafeArea: false,
    isScrollControlled: true,
    builder: (sheetContext) {
      final colors = _ActionSheetColors.of(sheetContext);
      final hairline = 1 / MediaQuery.devicePixelRatioOf(sheetContext);
      final maxHeight =
          MediaQuery.sizeOf(sheetContext).height * maxHeightFactor;

      Widget group({required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.panel),
            child: child,
          ),
        ),
      );

      final itemWidgets = <Widget>[];
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        final textColor =
            item.destructive ? colors.destructive : colors.primaryText;
        itemWidgets.add(
          AppPressable(
            semanticLabel: item.title,
            onTap: () => Navigator.of(sheetContext).pop(item.value),
            pressedColor: colors.itemHighlighted,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: item.subtitle == null ? 54 : 62,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      SizedBox(
                        width: 28,
                        child: Icon(item.icon, size: 20, color: textColor),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.listPrimary.copyWith(
                              color: textColor,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          if (item.subtitle?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.metadata.copyWith(
                                color: colors.secondaryText,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.trailingText?.trim().isNotEmpty == true) ...[
                      const SizedBox(width: AppSizes.paddingMd),
                      Text(
                        item.trailingText!,
                        style: AppTextStyles.metadata.copyWith(
                          color: item.selected
                              ? colors.standardAction
                              : colors.secondaryText,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (item.selected) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_rounded,
                        size: 19,
                        color: colors.standardAction,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        if (index != items.length - 1) {
          itemWidgets.add(
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: SizedBox(
                height: hairline,
                child: ColoredBox(color: colors.separator),
              ),
            ),
          );
        }
      }

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colors.secondaryText.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                ),
                group(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: maxHeight - (showCancel ? 82 : 20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title?.trim().isNotEmpty == true) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                            child: Text(
                              title!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.metadata.copyWith(
                                color: colors.secondaryText,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: hairline,
                            child: ColoredBox(color: colors.separator),
                          ),
                        ],
                        Flexible(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: itemWidgets,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showCancel) ...[
                  const SizedBox(height: 8),
                  group(
                    child: AppPressable(
                      semanticLabel: cancelText,
                      onTap: () => Navigator.of(sheetContext).pop(),
                      pressedColor: colors.itemHighlighted,
                      child: SizedBox(
                        height: 54,
                        child: Center(
                          child: Text(
                            cancelText,
                            style: AppTextStyles.listPrimary.copyWith(
                              color: colors.standardAction,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

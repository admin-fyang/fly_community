/// 消息长按上下文菜单组件。
///
/// 第一阶段 Telegram-iOS-inspired 重构：保留原有 MessageMenuAction 契约，
/// 仅升级 overlay、材质、按压状态、动效与 haptic，不触碰聊天业务逻辑。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_haptics.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/interaction/app_pressable.dart';

enum MessageMenuAction {
  reply,
  copy,
  multiSelect,
  recall,
  delete,
}

class _ContextMenuColors {
  const _ContextMenuColors({
    required this.dim,
    required this.panel,
    required this.sectionSeparator,
    required this.itemHighlighted,
    required this.primaryText,
    required this.destructive,
    required this.border,
  });

  final Color dim;
  final Color panel;
  final Color sectionSeparator;
  final Color itemHighlighted;
  final Color primaryText;
  final Color destructive;
  final Color border;

  static _ContextMenuColors of(BuildContext context) {
    final overlay = context.overlayTokens;
    if (!context.isDark) {
      return _ContextMenuColors(
        dim: overlay.dim,
        panel: overlay.panel,
        sectionSeparator: overlay.separator,
        itemHighlighted: overlay.itemHighlighted,
        primaryText: overlay.primaryText,
        destructive: overlay.destructive,
        border: overlay.separator.withValues(alpha: 0.72),
      );
    }

    // Telegram-iOS / DefaultDarkPresentationTheme.swift /
    // PresentationThemeContextMenu. ContextMenu uses a lighter glass surface
    // and stronger dimming than ActionSheet in the default Night theme.
    return const _ContextMenuColors(
      dim: Color(0x99000000),
      panel: Color(0xC7252525),
      sectionSeparator: Color(0x33000000),
      itemHighlighted: Color(0x26FFFFFF),
      primaryText: Color(0xFFFFFFFF),
      destructive: Color(0xFFEB5545),
      border: Color(0x00000000),
    );
  }
}

Future<MessageMenuAction?> showMessageContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required bool canRecall,
}) async {
  await AppHaptics.softImpact();
  if (!context.mounted) return null;
  return Navigator.of(context).push<MessageMenuAction>(
    _ContextMenuRoute(
      position: globalPosition,
      canRecall: canRecall,
      dim: _ContextMenuColors.of(context).dim,
    ),
  );
}

class _ContextMenuRoute extends PopupRoute<MessageMenuAction> {
  _ContextMenuRoute({
    required this.position,
    required this.canRecall,
    required this.dim,
  });

  final Offset position;
  final bool canRecall;
  final Color dim;

  @override
  Color? get barrierColor => dim;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => AppConstants.animNormal;

  @override
  Duration get reverseTransitionDuration => AppConstants.animFast;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    const menuWidth = 196.0;
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final itemCount = canRecall ? 7 : 6;
    final menuHeight = itemCount * 43.0 + 20;

    var left = position.dx - 18;
    var top = position.dy - 14;

    if (left + menuWidth > screen.width - AppSizes.paddingSm) {
      left = screen.width - menuWidth - AppSizes.paddingSm;
    }
    if (left < AppSizes.paddingSm) left = AppSizes.paddingSm;

    final maxBottom = screen.height - padding.bottom - AppSizes.paddingSm;
    if (top + menuHeight > maxBottom) {
      top = position.dy - menuHeight + 14;
    }
    final minTop = padding.top + AppSizes.paddingSm;
    if (top < minTop) top = minTop;

    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.telegramSlide,
      reverseCurve: AppMotion.exit,
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.035),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.965, end: 1).animate(curved),
                alignment: Alignment.topLeft,
                child: _MenuPanel(width: menuWidth, canRecall: canRecall),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.width, required this.canRecall});

  final double width;
  final bool canRecall;

  @override
  Widget build(BuildContext context) {
    final colors = _ContextMenuColors.of(context);
    final radius = BorderRadius.circular(14);
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: context.isDark ? 0.34 : 0.12,
              ),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: radius,
                border: Border.all(
                  color: colors.border,
                  width: 1 / MediaQuery.devicePixelRatioOf(context),
                ),
              ),
              child: SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _item(
                        context,
                        MessageMenuAction.reply,
                        'assets/icons/chat/reply.svg',
                        '回复',
                      ),
                      _item(
                        context,
                        MessageMenuAction.copy,
                        'assets/icons/chat/copy.svg',
                        '复制',
                      ),
                      _item(
                        context,
                        MessageMenuAction.multiSelect,
                        'assets/icons/chat/multi_select.svg',
                        '多选',
                      ),
                      _divider(context),
                      if (canRecall)
                        _item(
                          context,
                          MessageMenuAction.recall,
                          'assets/icons/chat/recall.svg',
                          '撤回',
                          danger: true,
                        ),
                      _item(
                        context,
                        MessageMenuAction.delete,
                        'assets/icons/chat/delete.svg',
                        '删除',
                        danger: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    final colors = _ContextMenuColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingItem),
      child: SizedBox(
        height: 1 / MediaQuery.devicePixelRatioOf(context),
        child: ColoredBox(color: colors.sectionSeparator),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    MessageMenuAction action,
    String iconAsset,
    String label, {
    bool danger = false,
  }) {
    final colors = _ContextMenuColors.of(context);
    final color = danger ? colors.destructive : colors.primaryText;
    return AppPressable(
      semanticLabel: label,
      onTap: () {
        AppHaptics.selection();
        Navigator.of(context).pop(action);
      },
      pressedColor: colors.itemHighlighted,
      child: SizedBox(
        height: 43,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingLg,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.messageBody.copyWith(
                    color: color,
                    fontSize: 15,
                    height: 20 / 15,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingItem),
              SizedBox(
                width: 22,
                child: Center(
                  child: SvgPicture.asset(
                    iconAsset,
                    width: 19,
                    height: 19,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 登录后一级底部导航。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/interaction/app_pressable.dart';
import '../main_navigation_controller.dart';
import '../../../shared/widgets/app_glass_capsule.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.currentTab,
    required this.onSelected,
  });

  final MainTab currentTab;
  final ValueChanged<MainTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final tabs = <MainTab>[
      MainTab.conversations,
      MainTab.contacts,
      MainTab.mine,
    ];
    return AppGlassCapsule(
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: _BottomNavigationItem(
                tab: tab,
                selected: currentTab == tab,
                onTap: () => onSelected(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final MainTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final color = selected ? semantic.accent : semantic.textSecondary;
    final (label, icon) = switch (tab) {
      MainTab.conversations => (
        '会话',
        selected
            ? Icons.chat_bubble_rounded
            : Icons.chat_bubble_outline_rounded,
      ),
      MainTab.contacts => (
        '通讯录',
        selected ? Icons.people_rounded : Icons.people_outline_rounded,
      ),
      MainTab.mine => (
        '我的',
        selected ? Icons.person_rounded : Icons.person_outline_rounded,
      ),
    };
    return Semantics(
      selected: selected,
      child: AppPressable(
        semanticLabel: label,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGlassCapsule.itemRadius),
        pressedColor: semantic.surfacePressed,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 仅对选中底板做透明度动画，不改变项目尺寸。
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1 : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: semantic.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(
                      AppGlassCapsule.itemRadius,
                    ),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: AppSizes.bottomNavigationIconSize,
                  color: color,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTextStyles.badgeLabel.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 全局搜索栏组件。
///
/// 提供统一的搜索栏外壳 [SearchAppBarShell] 与搜索输入行 [AppSearchField],
/// 首页 / 联系人 / 搜索页三处共用,保证外壳与输入样式一致。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../interaction/app_pressable.dart';
import '../navigation/app_navigation_button.dart';
import '../navigation/app_top_bar.dart';

/// 全局统一搜索栏外壳
///
/// 兼容原有搜索页面的入口，表面、安全区与状态图标委托给 AppTopBar。
/// 新页面优先使用 AppSearchAppBar，以便统一普通与搜索模式的完整交互。
class SearchAppBarShell extends StatelessWidget implements PreferredSizeWidget {
  const SearchAppBarShell({
    super.key,
    required this.child,
    this.backgroundColor,
    this.dividerColor,
  });

  final Widget child;

  /// 兼容已有调用；透明及磨砂底色统一由 AppTopBar 根据主题管理。
  final Color? backgroundColor;
  final Color? dividerColor;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.appBarHeight);

  @override
  Widget build(BuildContext context) => AppTopBar(child: child);
}

/// 全局统一搜索输入行
///
/// 返回图标 + 输入框(统一字号/hint 样式)+ 可选清除按钮。纯 Flutter 组件,
/// 不依赖 GetX;传入 [controller] 时自动在有文字时显示清除按钮。
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.onBack,
    required this.onChanged,
    this.controller,
    this.hint = '搜索...',
    this.autofocus = true,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final isDark = context.isDark;
    // Telegram-iOS Night / PresentationThemeNavigationSearchBar:
    // inputFill = white @ 10%, controls/placeholder = #8F8F8F, accent = white.
    // This is intentionally different from inline/chat-list search (#272728).
    final searchFill = isDark
        ? const Color(0x1AFFFFFF)
        : semantic.surfacePressed.withValues(alpha: 0.72);
    final searchControl = isDark
        ? const Color(0xFF8F8F8F)
        : semantic.textTertiary;
    final searchCursor = isDark ? Colors.white : semantic.accent;
    return Row(
      children: [
        AppNavigationButton(
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
          color: semantic.textPrimary,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: SizedBox(
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: searchFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(Icons.search_rounded, size: 18, color: searchControl),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: autofocus,
                      onChanged: onChanged,
                      cursorColor: searchCursor,
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
                          color: isDark
                              ? const Color(0xFF8F8F8F)
                              : semantic.placeholder,
                          fontSize: 14.5,
                          height: 18 / 14.5,
                        ),
                      ),
                    ),
                  ),
                  if (controller != null) _clearButton(context, controller!),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.paddingSm),
      ],
    );
  }

  Widget _clearButton(BuildContext context, TextEditingController c) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox(width: 8);
        return SizedBox(
          width: 32,
          height: 36,
          child: Center(
            child: ClipOval(
              child: AppPressable(
                semanticLabel: '清除搜索',
                onTap: () {
                  c.clear();
                  onChanged('');
                },
                normalColor: context.isDark
                    ? const Color(0xFF8F8F8F)
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

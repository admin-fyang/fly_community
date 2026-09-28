/// 主题装配。
///
/// 将颜色 / 字体 / 圆角等设计 token 组装为浅色与深色 [ThemeData],
/// 统一全局的表面、分割线、输入框、按钮等视觉基线。
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_semantic_colors.dart';
import 'chat_bubble_tokens.dart';
import 'chat_input_tokens.dart';
import 'chat_wallpaper_tokens.dart';
import 'conversation_list_tokens.dart';
import 'overlay_tokens.dart';
import 'app_sizes.dart';
import 'app_text_styles.dart';

/// 主题装配：把颜色 / 字体 / 圆角 token 组装成 [ThemeData.light] 与 [ThemeData.dark]
///
/// 风格基线：克制、扁平、无重阴影，用色阶层叠而非阴影构建层级（DESIGN 要求）。
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightOnPrimary,
      secondaryContainer: AppColors.lightBrandSoft,
      onSecondaryContainer: AppColors.lightOnBrandSoft,
      surface: AppColors.lightBackground,
      onSurface: AppColors.lightOnSurface,
      surfaceContainerLowest: AppColors.lightSurface,
      surfaceContainerLow: AppColors.lightSurfaceContainerLow,
      surfaceContainer: AppColors.lightSurfaceContainer,
      surfaceContainerHigh: AppColors.lightSurfaceContainerHigh,
      surfaceContainerHighest: AppColors.lightSurfaceContainerHighest,
      onSurfaceVariant: AppColors.lightOnSurfaceVariant,
      outline: AppColors.lightOutline,
      outlineVariant: AppColors.lightOutlineVariant,
      error: AppColors.lightError,
      onError: AppColors.lightOnError,
    ),
    tokens: AppColorTokens.light,
    appBarBackground: AppColors.lightSurface,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      surface: AppColors.darkBackground,
      onSurface: AppColors.darkOnSurface,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: AppColors.darkSurfaceContainerLow,
      surfaceContainer: AppColors.darkSurfaceContainer,
      surfaceContainerHigh: AppColors.darkSurfaceContainerHigh,
      surfaceContainerHighest: AppColors.darkSurfaceContainerHighest,
      onSurfaceVariant: AppColors.darkOnSurfaceVariant,
      outline: AppColors.darkOutline,
      outlineVariant: AppColors.darkOutlineVariant,
      error: AppColors.darkError,
      onError: AppColors.darkOnError,
    ),
    tokens: AppColorTokens.dark,
    appBarBackground: AppColors.darkHomeAppBar,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppColorTokens tokens,
    required Color appBarBackground,
  }) {
    final textTheme = AppTextStyles.buildTextTheme(
      onSurface: scheme.onSurface,
      onSurfaceVariant: scheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // 全局使用应用内置 HarmonyOS Sans SC，避免不同系统字体 fallback 造成
      // 中文字形、字宽、基线和视觉大小不一致。
      fontFamily: AppTextStyles.fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      extensions: [
        tokens,
        brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light,
        brightness == Brightness.dark
            ? ConversationListTokens.dark
            : ConversationListTokens.light,
        brightness == Brightness.dark
            ? ChatBubbleTokens.dark
            : ChatBubbleTokens.light,
        brightness == Brightness.dark
            ? ChatInputTokens.dark
            : ChatInputTokens.light,
        brightness == Brightness.dark
            ? ChatWallpaperTokens.dark
            : ChatWallpaperTokens.light,
        brightness == Brightness.dark ? OverlayTokens.dark : OverlayTokens.light,
      ],
      // 扁平化：去除 Material 默认阴影，用色阶区分层级
      appBarTheme: AppBarTheme(
        toolbarHeight: AppSizes.appBarHeight,
        backgroundColor: appBarBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.navTitleMobile.copyWith(
          color: scheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        thickness: 0.5,
        space: 0.5,
      ),
      // 未显式指定颜色的局部、分页加载统一使用品牌强调色。
      // 按钮内反色加载仍由按钮组件显式使用白色，保证对比度。
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.brand,
        linearTrackColor: scheme.onSurface.withValues(alpha: 0.08),
        circularTrackColor: scheme.onSurface.withValues(alpha: 0.08),
      ),
      // Telegram-iOS Night / PresentationThemeList.scrollIndicatorColor
      // = white @ 50%. Only the color is overridden; thickness, visibility,
      // radius and interaction keep Flutter's existing behavior.
      scrollbarTheme: brightness == Brightness.dark
          ? const ScrollbarThemeData(
              thumbColor: WidgetStatePropertyAll(Color(0x80FFFFFF)),
            )
          : null,
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
        ),
      ),
      splashFactory: InkRipple.splashFactory,
      // 常规输入框统一沿用登录页的 8px 圆角；特殊输入组件必须显式覆盖各状态边框。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          borderSide: BorderSide.none,
        ),
        // 聚焦态显式使用同一圆角，避免状态切换时形状发生变化。
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingLg,
          vertical: AppSizes.paddingMd,
        ),
        hintStyle: AppTextStyles.messageBody.copyWith(
          // Telegram-iOS Night freeInputField placeholder = #98989E.
          // Navigation search keeps its separate #8F8F8F role locally.
          color: brightness == Brightness.dark
              ? const Color(0xFF98989E)
              : scheme.outline,
        ),
      ),
      // 操作按钮统一去掉 Material elevation / splash，靠轻微 overlay 表达按压。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: tokens.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.08),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.36),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: AppTextStyles.messageBody.copyWith(
            fontSize: 15.5,
            height: 20 / 15.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.brand,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: AppTextStyles.messageBody.copyWith(
            fontSize: 15.5,
            height: 20 / 15.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.brand,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          ),
          textStyle: AppTextStyles.messageBody.copyWith(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

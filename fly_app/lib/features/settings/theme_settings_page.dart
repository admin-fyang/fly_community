/// 主题设置页。
///
/// 按 `资料/UI/设置/主题设置.html` 实现主题预览和三种主题模式选择。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/theme/theme_transition_layer.dart';
import '../../data/enums/theme_mode_type.dart';
import 'widgets/settings_scaffold.dart';

/// 主题状态由全局 [ThemeController] 统一维护，页面只负责展示和接收选择事件。
class ThemeSettingsPage extends GetView<ThemeController> {
  const ThemeSettingsPage({super.key});

  static const double _contentMaxWidth = 672;
  static const Duration _selectionDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SettingsScaffold(
      title: '主题设置',
      appBarIconColor: context.semanticColors.textPrimary,
      showAppBarDivider: false,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSizes.paddingLg,
        AppSizes.paddingXl,
        AppSizes.paddingLg,
        AppSizes.paddingXl * 4,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.paddingSm,
                  ),
                  child: Text(
                    '主题模式',
                    style: AppTextStyles.metadata.copyWith(
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.paddingLg),
                Obx(() => _previewOptions(context, controller.mode)),
                const SizedBox(height: AppSizes.paddingXl * 1.5),
                Obx(() => _radioOptions(context, controller.mode)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewOptions(BuildContext context, ThemeModeType selectedMode) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mode in ThemeModeType.values) ...[
          Expanded(
            child: _ThemePreviewCard(
              key: ValueKey('theme-preview-${mode.name}'),
              mode: mode,
              selected: selectedMode == mode,
              onTap: (origin) => _changeTheme(context, mode, origin),
            ),
          ),
          if (mode != ThemeModeType.values.last)
            const SizedBox(width: AppSizes.paddingLg),
        ],
      ],
    );
  }

  Widget _radioOptions(BuildContext context, ThemeModeType selectedMode) {
    final options = <(ThemeModeType, IconData)>[
      (ThemeModeType.light, Icons.light_mode_outlined),
      (ThemeModeType.dark, Icons.dark_mode_outlined),
      (ThemeModeType.system, Icons.brightness_auto_outlined),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.semanticColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
      ),
      child: RadioGroup<ThemeModeType>(
        groupValue: selectedMode,
        onChanged: (mode) {
          if (mode != null) _changeTheme(context, mode, _screenCenter(context));
        },
        child: Column(
          children: [
            for (var index = 0; index < options.length; index++) ...[
              _ThemeModeTile(
                mode: options[index].$1,
                icon: options[index].$2,
                selected: selectedMode == options[index].$1,
                onTap: (origin) =>
                    _changeTheme(context, options[index].$1, origin),
              ),
              if (index < options.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.paddingLg,
                  ),
                  child: Divider(
                    height: AppSizes.hairline,
                    color: context.tokens.divider,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changeTheme(
    BuildContext context,
    ThemeModeType mode,
    Offset origin,
  ) => ThemeTransitionLayer.of(
    context,
  ).changeTheme(mode, origin: origin);

  Offset _screenCenter(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Offset(size.width / 2, size.height / 2);
  }
}

/// 三种模式使用同一预览卡片，只替换预览画布内容。
class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    super.key,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeModeType mode;
  final bool selected;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    Offset tapOrigin = Offset.zero;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTapDown: (details) => tapOrigin = details.globalPosition,
        onTap: () => onTap(tapOrigin),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: AnimatedContainer(
          duration: ThemeSettingsPage._selectionDuration,
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          decoration: BoxDecoration(
            color: context.semanticColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusGrouped),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _ThemePreviewCanvas(mode: mode),
                  ),
                  const SizedBox(height: AppSizes.paddingMd),
                  Text(
                    mode.settingsLabel,
                    style: AppTextStyles.listPrimary.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Icon(
                    key: ValueKey('theme-preview-selected-${mode.name}'),
                    Icons.check_circle,
                    color: context.tokens.brand,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻量模拟聊天界面，帮助用户在切换前理解主题差异。
class _ThemePreviewCanvas extends StatelessWidget {
  const _ThemePreviewCanvas({required this.mode});

  final ThemeModeType mode;

  /// 预览骨架在标准尺寸下所需的最小高度。
  ///
  /// 三列预览在窄屏上会产生小数像素高度，因此内部骨架必须根据实际约束等比
  /// 收缩，不能依赖 [Spacer] 吸收负空间，否则会触发 RenderFlex 溢出。
  static const double _minimumContentHeight =
      AppSizes.paddingSm * 3 + AppSizes.paddingXl * 2 + AppSizes.paddingMd;

  @override
  Widget build(BuildContext context) {
    if (mode == ThemeModeType.system) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.lightBackground, AppColors.darkBackground],
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          border: Border.all(color: context.tokens.divider),
        ),
        child: Icon(
          Icons.brightness_auto_outlined,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          size: 32,
        ),
      );
    }

    final dark = mode == ThemeModeType.dark;
    final background = dark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    final outgoing = dark
        ? AppColors.darkBubbleSelf
        : AppColors.lightBubbleSelf;
    final subtle = dark
        ? Colors.white.withValues(alpha: 0.1)
        : context.tokens.brand.withValues(alpha: 0.2);

    return Container(
      padding: const EdgeInsets.all(AppSizes.paddingSm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
        border: Border.all(
          color: dark ? AppColors.darkSurface : context.tokens.divider,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.hasBoundedHeight
              ? (constraints.maxHeight / _minimumContentHeight).clamp(0.0, 1.0)
              : 1.0;
          double scaled(double value) => value * scale;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: 0.55,
                child: Container(
                  height: scaled(AppSizes.paddingSm),
                  decoration: BoxDecoration(
                    color: subtle,
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                ),
              ),
              SizedBox(height: scaled(AppSizes.paddingSm)),
              FractionallySizedBox(
                widthFactor: 0.78,
                child: Container(
                  height: scaled(AppSizes.paddingXl),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
                  ),
                ),
              ),
              SizedBox(height: scaled(AppSizes.paddingSm)),
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.68,
                  child: Container(
                    height: scaled(AppSizes.paddingXl),
                    decoration: BoxDecoration(
                      color: outgoing,
                      borderRadius: BorderRadius.circular(
                        AppSizes.radiusDefault,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: scaled(AppSizes.paddingMd),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 下方列表提供更大的点击区域，并与预览卡片保持同一选中状态。
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.mode,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ThemeModeType mode;
  final IconData icon;
  final bool selected;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    Offset tapOrigin = Offset.zero;
    return InkWell(
      key: ValueKey('theme-option-${mode.name}'),
      onTapDown: (details) => tapOrigin = details.globalPosition,
      onTap: () => onTap(tapOrigin),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? (context.isDark ? Colors.white : context.tokens.brand)
                  : context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSizes.paddingMd),
            Expanded(
              child: Text(
                mode.settingsLabel,
                style: AppTextStyles.listPrimary.copyWith(
                  color: context.colorScheme.onSurface,
                ),
              ),
            ),
            Radio<ThemeModeType>(
              value: mode,
              activeColor: context.isDark
                  ? Colors.white
                  : context.tokens.brand,
            ),
          ],
        ),
      ),
    );
  }
}

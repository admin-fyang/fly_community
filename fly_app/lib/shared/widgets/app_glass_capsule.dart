/// 底部导航与会话多选操作共用的轻量毛玻璃胶囊。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_colors.dart';

/// 统一胶囊的尺寸、浅深主题底色、细描边与轻阴影。
///
/// 只负责视觉容器，按钮状态和点击事件由调用方提供。
/// 阴影位于裁剪层外；单层背景模糊被 ClipRRect 限定在胶囊内部，
/// 避免模糊整页。容器不处理安全区，调用方应只计算一次底部安全区。
class AppGlassCapsule extends StatelessWidget {
  const AppGlassCapsule({super.key, required this.child});

  /// 紧凑胶囊的固定高度与内边距，导航及多选操作统一引用。
  static const height = 56.0;
  static const contentPadding = 4.0;
  static const horizontalMargin = 48.0;
  static const bottomGap = 8.0;
  static const itemRadius = (height - contentPadding * 2) / 2;

  /// 通常传入等宽按钮组成的 Row，不在这里处理业务状态。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final radius = BorderRadius.circular(height / 2);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.16 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: height,
            padding: const EdgeInsets.all(contentPadding),
            decoration: BoxDecoration(
              color:
                  (context.isDark
                          ? AppColors.darkHomeAppBar
                          : semantic.backgroundPrimary)
                      .withValues(alpha: context.isDark ? 0.78 : 0.72),
              borderRadius: radius,
              border: Border.all(
                color: semantic.separator.withValues(alpha: 0.5),
                width: 1 / MediaQuery.devicePixelRatioOf(context),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Telegram 风格的普通页面层级切换动画。
///
/// 前进时新页面从右侧完整进入，原页面向左后退 20% 并轻微变暗；
/// 返回时严格反向恢复。该动画只用于普通页面，来电、认证和媒体预览等
/// 特殊场景由各自路由继续维护独立过渡。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_motion.dart';

/// 普通页面的 Telegram 层级过渡。
class TelegramPageTransition extends CustomTransition {
  TelegramPageTransition();

  /// Telegram-iOS 源码提取的 slide cubic。
  static const Curve _curve = AppMotion.telegramSlide;

  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }

    final direction =
        Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final primary = CurvedAnimation(
      parent: animation,
      curve: _curve,
      reverseCurve: _curve,
    );
    final secondary = CurvedAnimation(
      parent: secondaryAnimation,
      curve: _curve,
      reverseCurve: _curve,
    );

    // 当前路由作为新页面时从右侧进入；作为旧页面时由 secondaryAnimation
    // 驱动向左后退并轻微变暗，从而保持 Telegram 的前后层级关系。
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(direction, 0),
        end: Offset.zero,
      ).animate(primary),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: Offset(-0.2 * direction, 0),
        ).animate(secondary),
        // Telegram 的旧页面位于黑色底层上方，降低到 90% 透明度后产生
        // 轻微压暗效果，而不是额外叠加重色蒙层。
        child: ColoredBox(
          color: Theme.of(context).colorScheme.scrim,
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.9).animate(secondary),
            child: child,
          ),
        ),
      ),
    );
  }
}

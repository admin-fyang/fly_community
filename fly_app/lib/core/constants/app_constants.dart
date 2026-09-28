import 'package:flutter/animation.dart';

/// 全局常量、轻量动效时长与曲线。
///
/// 视觉基准页统一使用 80 / 160 / 220ms 三档节奏：
/// - 80ms：即时按压反馈；
/// - 160ms：局部状态切换；
/// - 220ms：顶栏、面板等结构切换。
class AppConstants {
  AppConstants._();

  static const String appName = 'Messenger';

  static const Duration animInstant = Duration(milliseconds: 80);
  static const Duration animFast = Duration(milliseconds: 160);
  static const Duration animNormal = Duration(milliseconds: 220);
  static const Duration animSlow = Duration(milliseconds: 300);

  static const Curve motionStandard = Curves.easeOutCubic;
  static const Curve motionExit = Curves.easeInCubic;
}

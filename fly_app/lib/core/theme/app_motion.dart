/// Shared motion curves for presentation-layer transitions.
library;

import 'package:flutter/animation.dart';

abstract final class AppMotion {
  /// Source-informed Telegram-iOS slide curve.
  static const Curve telegramSlide = Cubic(0.33, 0.52, 0.25, 0.99);

  /// Local interaction feedback. Durations remain in AppConstants.
  static const Curve press = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Semantic haptic feedback service.
library;

import 'package:flutter/services.dart';

abstract final class AppHaptics {
  static Future<void> selection() => HapticFeedback.selectionClick();
  static Future<void> softImpact() => HapticFeedback.lightImpact();
  static Future<void> impact() => HapticFeedback.mediumImpact();

  /// Flutter does not expose iOS notification haptics directly; these mappings
  /// keep callsites semantic while remaining cross-platform and compile-safe.
  static Future<void> success() => HapticFeedback.lightImpact();
  static Future<void> warning() => HapticFeedback.mediumImpact();
  static Future<void> error() => HapticFeedback.heavyImpact();
}

/// 主题控制器。
///
/// 维护当前主题模式(日间/夜间/跟随系统)，通过 GetMaterialApp 的
/// themeMode 响应式驱动整个 App 切换，并持久化到当前设备。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/local/app_settings_storage.dart';
import '../../data/enums/theme_mode_type.dart';

/// 主题切换状态
///
/// 通过 GetMaterialApp 的 themeMode 响应式驱动整个 App，并恢复上次选择。
class ThemeController extends GetxController {
  ThemeController(this._storage);

  final AppSettingsStorage _storage;

  // final _mode = ThemeModeType.dark.obs; // 原型以深色为主，默认夜间
  final _mode = ThemeModeType.light.obs; // 原型以白色色为主，默认白天

  @override
  void onInit() {
    super.onInit();
    _restore();
  }

  ThemeModeType get mode => _mode.value;

  /// 映射为 Flutter 的 ThemeMode，供 GetMaterialApp 使用
  ThemeMode get themeMode {
    switch (_mode.value) {
      case ThemeModeType.light:
        return ThemeMode.light;
      case ThemeModeType.dark:
        return ThemeMode.dark;
      case ThemeModeType.system:
        return ThemeMode.system;
    }
  }

  /// 循环切换：日间 → 夜间 → 跟随系统
  void toggle() => setMode(_mode.value.next);

  /// 设置为指定模式,并立即通知 GetX 切换全局主题
  Future<void> setMode(ThemeModeType mode) async {
    final previous = _mode.value;
    _mode.value = mode;
    Get.changeThemeMode(themeMode);
    try {
      await _storage.saveThemeMode(mode);
    } catch (_) {
      _mode.value = previous;
      Get.changeThemeMode(themeMode);
    }
  }

  Future<void> _restore() async {
    try {
      _mode.value = await _storage.readThemeMode();
      Get.changeThemeMode(themeMode);
    } catch (_) {
      // 本地偏好损坏时继续使用安全默认值，不阻断应用启动。
    }
  }
}

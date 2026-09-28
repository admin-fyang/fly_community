/// 应用运行平台定义。
///
/// 平台识别统一收敛在此文件，业务层不得重复组合 `kIsWeb`、
/// `defaultTargetPlatform` 等条件，避免拆分后的平台规则散落在页面中。
library;

import 'package:flutter/foundation.dart';

/// 产品支持的运行平台。
enum AppPlatform {
  android,
  ios,
  web,
  unsupported,
}

/// 当前 Flutter Engine 对应的产品平台。
AppPlatform get currentAppPlatform {
  if (kIsWeb) return AppPlatform.web;

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.iOS => AppPlatform.ios,
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => AppPlatform.unsupported,
  };
}

/// 后端设备枚举使用的稳定字符串。
extension AppPlatformWireName on AppPlatform {
  String get wireName => switch (this) {
    AppPlatform.android => 'android',
    AppPlatform.ios => 'ios',
    AppPlatform.web => 'web',
    AppPlatform.unsupported => 'unsupported',
  };
}

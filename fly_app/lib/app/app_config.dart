/// 应用级配置。
///
/// 集中管理构建期常量(调试横幅、调试模式判断),第一阶段保持轻量。
library;

// import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import 'platform/app_platform_capabilities.dart';

/// 应用级配置。
class AppConfig {
  AppConfig._();

  /// 是否展示调试横幅
  static const bool showDebugBanner = false;

  /// 是否处于调试构建
  static bool get isDebug => kDebugMode;

  /// 产品约定仅 Android/iOS 展示扫码入口。
  static bool get supportsQrScanner =>
      AppPlatformCapabilities.current.supportsQrScanner;

  /// 社区版 API 地址由构建参数指定；Web 同域部署时默认使用页面来源。
  static final String apiBaseUrl = const String.fromEnvironment(
    'FLYIM_API_BASE_URL',
  ).trim().isNotEmpty
      ? const String.fromEnvironment('FLYIM_API_BASE_URL').trim()
      : (kIsWeb ? Uri.base.origin : 'http://127.0.0.1:8787');

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}

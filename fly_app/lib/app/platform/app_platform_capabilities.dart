/// 平台能力配置。
///
/// 页面只读取能力结果，不自行判断操作系统，避免平台规则散落在 Widget 中。
library;

import 'app_platform.dart';

/// 描述当前平台可向用户提供的产品能力。
final class AppPlatformCapabilities {
  const AppPlatformCapabilities({
    required this.platform,
    required this.supportsQrScanner,
    required this.supportsFirebasePush,
    required this.supportsForegroundRealtime,
    required this.supportsAppPackageInstall,
    required this.usesWebStorage,
  });

  factory AppPlatformCapabilities.forPlatform(AppPlatform platform) {
    final isAndroid = platform == AppPlatform.android;
    final isMobile = isAndroid || platform == AppPlatform.ios;
    return AppPlatformCapabilities(
      platform: platform,
      supportsQrScanner: isMobile,
      supportsFirebasePush: isAndroid,
      supportsForegroundRealtime: isAndroid,
      supportsAppPackageInstall: isAndroid,
      usesWebStorage: platform == AppPlatform.web,
    );
  }

  /// 当前运行环境的能力快照。
  static final current = AppPlatformCapabilities.forPlatform(
    currentAppPlatform,
  );

  final AppPlatform platform;
  final bool supportsQrScanner;
  final bool supportsFirebasePush;
  final bool supportsForegroundRealtime;
  final bool supportsAppPackageInstall;
  final bool usesWebStorage;

}

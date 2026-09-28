import 'system_time_service.dart';

/// 非原生平台通知品牌资源为空操作。
class NotificationBrandingService {
  NotificationBrandingService(this._systemConfig);

  // 保持与原生实现一致的构造签名。
  final SystemTimeService _systemConfig;

  Future<String?> refresh() async {
    _systemConfig.revision.value;
    return null;
  }

  Future<String?> resolveLargeIconPath() => refresh();

  static Future<String?> readCachedLargeIconPath({String? expectedUrl}) async =>
      null;
}

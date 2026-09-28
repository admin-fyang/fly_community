/// 客户端设备信息服务。
///
/// device_id 是安装实例 UUID，不使用不可控的硬件标识。
library;

import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/platform/app_platform.dart';
import '../local/session_storage.dart';

class DeviceService {
  DeviceService(this._storage, {Future<String?> Function()? deviceNameLoader})
    : _deviceNameLoader = deviceNameLoader;

  final Future<String?> Function()? _deviceNameLoader;
  Future<String>? _deviceName;
  Future<String>? _installationId;

  /// 平台插件只读取一次，并合并并发请求；采集失败不阻断认证和消息同步。
  Future<String> _readDeviceName() => _deviceName ??= _loadDeviceName();

  Future<String> _loadDeviceName() async {
    try {
      final name = (await (_deviceNameLoader?.call() ?? _platformDeviceName())
          .timeout(const Duration(seconds: 2)))?.trim();
      if (name != null && name.isNotEmpty) {
        // 与后端 device_name 的 128 字符上限一致，按字符截断避免拆开代理对。
        return String.fromCharCodes(name.runes.take(128));
      }
    } catch (_) {
      // 权限限制、插件不可用或宿主异常统一回退，设备 UUID 保持不变。
    }
    // return 'Flutter ${_platformLabel(platform)}';
    return _platformLabel(platform);
  }

  Future<String?> _platformDeviceName() async {
    final info = DeviceInfoPlugin();
    switch (platform) {
      case 'android':
        final device = await info.androidInfo;
        return '${device.brand} ${device.model}';
      case 'ios':
        return (await info.iosInfo).utsname.machine;
      case 'macos':
        return (await info.macOsInfo).model;
      case 'windows':
        final device = await info.windowsInfo;
        return '${device.productName} ${device.displayVersion}';
      case 'linux':
        return (await info.linuxInfo).prettyName;
      case 'web':
        final browser = await info.webBrowserInfo;
        return '${browser.browserName.name} ${browser.platform ?? 'Web'}';
      default:
        return null;
    }
  }

  final SessionStorage _storage;
  static const _uuid = Uuid();
  static String _appVersion = '0.0.0';
  static int _appVersionCode = 1;

  static String get appVersion => _appVersion;
  static int get appVersionCode => _appVersionCode;

  /// 从当前已安装应用读取真实版本，禁止用客户端常量模拟构建号。
  static Future<void> initializeVersion() async {
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version.trim().isEmpty ? '0.0.0' : info.version.trim();
    _appVersionCode = int.tryParse(info.buildNumber.trim()) ?? 1;
  }

  /// 当前客户端运行平台。
  ///
  /// 请求头和登录设备信息必须复用同一枚举，避免后端收到互相矛盾的平台值。
  String get platform => currentAppPlatform.wireName;

  Future<String> _readInstallationId() async {
    var deviceId = await _storage.readDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await _storage.saveDeviceId(deviceId);
    }
    return deviceId;
  }

  Future<Map<String, dynamic>> requestPayload() async {
    final task = _installationId ??= _readInstallationId();
    late final String deviceId;
    try {
      deviceId = await task;
    } catch (_) {
      if (identical(_installationId, task)) _installationId = null;
      rethrow;
    }
    final currentPlatform = platform;
    return {
      'device_id': deviceId,
      'platform': currentPlatform,
      'device_name': await _readDeviceName(),
      'app_version': appVersion,
    };
  }

  String _platformLabel(String platform) {
    return switch (platform) {
      'ios' => 'iOS',
      'web' => 'Web',
      _ => '${platform[0].toUpperCase()}${platform.substring(1)}',
    };
  }
}

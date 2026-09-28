/// 公开系统配置缓存。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/system_config_model.dart';

class SystemConfigStorage {
  SystemConfigStorage({
    required String sourceBaseUrl,
    Future<SharedPreferences>? preferences,
  }) : _configKey = _keyFor(sourceBaseUrl),
       _preferences = preferences ?? SharedPreferences.getInstance();

  /// 系统配置属于其 API 来源。地址变化后必须使用独立缓存，禁止让旧服务器
  /// 的 configVersion 或协议 URL 污染新服务器返回的配置。
  static String _keyFor(String sourceBaseUrl) {
    final normalized = sourceBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return 'system.public_config.${Uri.encodeComponent(normalized)}';
  }

  final String _configKey;
  final Future<SharedPreferences> _preferences;

  /// 前台服务与主 Isolate 不共享内存缓存，检查后端开关前必须刷新磁盘值。
  Future<void> reload() async => (await _preferences).reload();

  Future<SystemConfigModel?> read() async {
    final raw = (await _preferences).getString(_configKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SystemConfigModel.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SystemConfigModel config) async {
    await (await _preferences).setString(
      _configKey,
      jsonEncode(config.toJson()),
    );
  }
}

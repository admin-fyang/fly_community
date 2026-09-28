/// 设备管理中的有效登录会话；同一安装实例可以包含多个会话。
library;

class DeviceSession {
  const DeviceSession({
    required this.sessionId,
    required this.deviceId,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.createdAt,
    this.lastActiveAt,
    this.loginIp,
  });

  final String sessionId;
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final String? loginIp;

  /// 只接受服务端字符串标识，避免脏数据让退出操作指向错误会话。
  factory DeviceSession.fromJson(Object? value) {
    try {
      if (value is! Map) throw const FormatException();
      final sessionId = _text(value['session_id']);
      final deviceId = _text(value['device_id']);
      if (sessionId == null || deviceId == null) {
        throw const FormatException();
      }
      return DeviceSession(
        sessionId: sessionId,
        deviceId: deviceId,
        deviceName: _text(value['device_name']),
        platform: _text(value['platform']),
        appVersion: _text(value['app_version']),
        createdAt: _time(value['created_at']),
        lastActiveAt: _time(value['last_active_at']),
        loginIp: _text(value['login_ip']),
      );
    } catch (_) {
      throw const FormatException('登录设备信息格式不正确');
    }
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// 可选时间损坏时显示暂无记录，不影响其他设备信息读取。
  static DateTime? _time(Object? value) {
    if (value is! int || value <= 0 || value > 253402300799) return null;
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
}

/// 当前会话独立返回，其他会话使用不透明游标分页。
class DeviceSessionPage {
  const DeviceSessionPage({
    required this.currentSession,
    required this.items,
    this.nextCursor,
  });

  final DeviceSession currentSession;
  final List<DeviceSession> items;
  final String? nextCursor;

  factory DeviceSessionPage.fromJson(Object? value) {
    try {
      if (value is! Map || value['items'] is! List) {
        throw const FormatException();
      }
      final cursor = value['next_cursor'];
      if (cursor != null && (cursor is! String || cursor.trim().isEmpty)) {
        throw const FormatException();
      }
      return DeviceSessionPage(
        currentSession: DeviceSession.fromJson(value['current_session']),
        items: List.unmodifiable(
          (value['items'] as List).map(DeviceSession.fromJson),
        ),
        nextCursor: cursor as String?,
      );
    } catch (_) {
      throw const FormatException('设备列表格式不正确，请稍后重试');
    }
  }
}

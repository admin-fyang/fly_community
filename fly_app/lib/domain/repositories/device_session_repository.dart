/// 登录设备会话仓库；不暴露凭证，不承担 UI 反馈。
library;

import '../entities/device_session.dart';

abstract interface class DeviceSessionRepository {
  Future<DeviceSessionPage> getSessions({String? cursor});

  /// 成功返回表示服务端已确认撤销；超时不等于撤销失败。
  Future<void> revokeSession(String sessionId);
}

/// 设备管理 HTTP 接入，复用统一认证、响应和异常解析。
library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/entities/device_session.dart';
import '../../domain/repositories/device_session_repository.dart';

class DeviceSessionRepositoryImpl implements DeviceSessionRepository {
  const DeviceSessionRepositoryImpl(this._client);

  final ApiClient _client;

  @override
  Future<DeviceSessionPage> getSessions({String? cursor}) =>
      _client.get<DeviceSessionPage>(
        Uri(
          path: ApiPaths.authSessions,
          queryParameters: {
            'limit': '20',
            if (cursor != null) 'cursor': cursor,
          },
        ).toString(),
        decoder: DeviceSessionPage.fromJson,
        // 页面负责刷新反馈，避免全局恢复队列在页面销毁后保留该查询。
        retry: false,
      );

  @override
  Future<void> revokeSession(String sessionId) async {
    await _client.delete<String>(
      ApiPaths.authSession(sessionId),
      decoder: (data) {
        if (data is! Map || data['session_id'] != sessionId) {
          throw const FormatException('服务端未确认目标登录会话，请刷新设备列表');
        }
        return sessionId;
      },
    );
  }
}

/// Android 前台服务 Isolate 使用的最小 Centrifugo 凭证客户端。
///
/// 后台引擎不创建 GetX、页面、SQLite 或完整业务仓储，只通过统一 Dio、
/// BaseResponse 和认证拦截器获取短期连接凭证。
library;

import 'package:dio/dio.dart';

import '../../app/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../local/session_storage.dart';
import '../models/im_api_models.dart';
import '../network/auth_interceptor.dart';
import '../network/request_id_interceptor.dart';

class BackgroundRealtimeCredentialClient {
  BackgroundRealtimeCredentialClient(this._storage)
    : _client = ApiClient(
        Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              sendTimeout: AppConfig.connectTimeout,
              contentType: Headers.jsonContentType,
              headers: const {'X-Client-Platform': 'android'},
            ),
          )
          ..interceptors.add(RequestIdInterceptor())
          ..interceptors.add(AuthInterceptor(_storage)),
      );

  final SessionStorage _storage;
  final ApiClient _client;

  Future<CentrifugoConnectionToken> load() async {
    await _storage.reload();
    if (!await _storage.hasSession()) {
      throw StateError('后台长连接启动时没有有效登录会话');
    }
    return _client.post<CentrifugoConnectionToken>(
      ApiPaths.imCentrifugoToken,
      decoder: (data) => CentrifugoConnectionToken.fromJson(_object(data)),
    );
  }
}

Map<String, dynamic> _object(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

/// 客户端运行平台请求头拦截器。
///
/// 所有业务 API 都携带同一平台标识，供后端进行环境地址选择、兼容性分析、
/// 审计和灰度策略。对象存储直传使用独立 Dio，不会附加业务请求头。
library;

import 'package:dio/dio.dart';

import '../services/device_service.dart';

class ClientPlatformInterceptor extends Interceptor {
  ClientPlatformInterceptor(this._deviceService);

  static const headerName = 'X-Client-Platform';

  final DeviceService _deviceService;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers[headerName] = _deviceService.platform;
    handler.next(options);
  }
}

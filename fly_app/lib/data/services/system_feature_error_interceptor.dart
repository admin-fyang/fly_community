/// 社区版公共配置错误拦截器。
///
/// 基础功能由服务端返回原始业务错误，客户端不维护商业功能跳转状态。
library;

import 'package:dio/dio.dart';

final class SystemFeatureErrorInterceptor extends Interceptor {
  SystemFeatureErrorInterceptor(Object config);
}

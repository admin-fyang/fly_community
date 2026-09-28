/// 系统配置路由守卫。
///
/// 页面入口隐藏只是展示约束；路由守卫负责阻止深链、历史路由和程序化跳转
/// 绕过服务端下发的公共功能开关。
library;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../data/services/system_time_service.dart';
import '../shared/utils/app_toast.dart';
import 'app_routes.dart';

enum SystemFeature { registration }

final class SystemFeatureMiddleware extends GetMiddleware {
  SystemFeatureMiddleware(this.feature);

  final SystemFeature feature;

  @override
  RouteSettings? redirect(String? route) {
    final config = Get.find<SystemTimeService>();
    final enabled = config.canRegister;
    if (enabled) return null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppToast.warning(
        '注册功能已关闭',
      );
    });
    return RouteSettings(
      name: AppRoutes.login,
    );
  }
}

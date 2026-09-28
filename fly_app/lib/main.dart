/// 应用入口。
///
/// 负责初始化 Flutter 引擎绑定、注入全局依赖(主题控制器等),然后启动根组件 [App]。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'app/app.dart';
import 'app/initial_binding.dart';
import 'core/session/session_controller.dart';
import 'data/services/device_service.dart';
import 'data/services/im_lifecycle_service.dart';
import 'data/services/notification_branding_service.dart';
import 'data/services/system_time_service.dart';
import 'features/notifications/notification_unread_controller.dart';
import 'routes/app_routes.dart';
import 'shared/utils/app_toast.dart';


/// 程序入口:确保绑定就绪 → 注入全局依赖 → 运行应用
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceService.initializeVersion();
  tz_data.initializeTimeZones();
  // 先注入全局依赖并恢复会话，避免启动后先闪现登录页再跳转。
  InitialBinding().dependencies();
  await Get.find<SystemTimeService>().restoreCachedConfig();
  final hasSession = await Get.find<SessionController>().restore();

  runApp(
    App(initialRoute: hasSession ? AppRoutes.conversations : AppRoutes.login),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_refreshSystemConfigAndCheckUpdate());
  });
  if (hasSession) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_activateRestoredImSession());
      unawaited(Get.find<NotificationUnreadController>().refreshCount());
    });
  }
}

Future<void> _refreshSystemConfigAndCheckUpdate() async {
  final result = await Get.find<SystemTimeService>().refresh(force: true);
  if (!result.success && result.usedDefault) {
    AppToast.warning('系统时间配置获取失败，当前使用默认时区');
  }
  if (result.success) {
    unawaited(Get.find<NotificationBrandingService>().refresh());
  }
}

Future<void> _activateRestoredImSession() async {
  final result = await Get.find<ImLifecycleService>().activateSession();
  if (result.shouldWarnSync) {
    // AppToast.warning('消息同步暂时失败，将自动重试');
  }
}

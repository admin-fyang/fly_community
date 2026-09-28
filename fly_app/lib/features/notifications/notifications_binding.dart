/// 消息通知页依赖注入。
///
/// 进入消息通知页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import 'notifications_controller.dart';

class NotificationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<NotificationsController>(() => NotificationsController());
  }
}

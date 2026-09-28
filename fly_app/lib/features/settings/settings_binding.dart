/// 设置主页依赖注入。
library;

import 'package:get/get.dart';

import 'settings_controller.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SettingsController>(() => SettingsController());
  }
}

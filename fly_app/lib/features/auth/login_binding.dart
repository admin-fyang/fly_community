/// 登录页依赖注入。
///
/// 进入登录页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import 'login_controller.dart';

class LoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LoginController>(() => LoginController());
  }
}

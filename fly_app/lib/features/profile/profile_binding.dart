/// 用户资料页依赖注入。
///
/// 进入好友/陌生人资料页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import 'profile_controller.dart';

class ProfileBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProfileController>(() => ProfileController());
  }
}

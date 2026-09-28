/// 注册页依赖注入。
///
/// 进入注册页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import '../../shared/services/avatar_picker_service.dart';
import 'register_controller.dart';

class RegisterBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<AvatarPickerService>()) {
      Get.lazyPut<AvatarPickerService>(() => ImagePickerAvatarService());
    }
    Get.lazyPut<RegisterController>(() => RegisterController());
  }
}

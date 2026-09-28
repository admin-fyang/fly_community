/// 编辑个人资料页依赖注入。
library;

import 'package:get/get.dart';

import 'edit_profile_controller.dart';
import '../../shared/services/avatar_picker_service.dart';

class EditProfileBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<AvatarPickerService>()) {
      Get.lazyPut<AvatarPickerService>(() => ImagePickerAvatarService());
    }
    Get.lazyPut<EditProfileController>(() => EditProfileController());
  }
}

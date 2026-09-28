/// 联系人页依赖注入。
///
/// 进入联系人页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import 'contacts_controller.dart';

class ContactsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ContactsController>(() => ContactsController());
  }
}

/// 会话列表依赖注入。
///
/// 进入会话列表(首页)时惰性注册其控制器。
library;

import 'package:get/get.dart';

import 'conversations_controller.dart';

class ConversationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ConversationsController>(() => ConversationsController());
  }
}

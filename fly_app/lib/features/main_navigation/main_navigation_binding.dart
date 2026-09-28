/// 主导航外壳及三个一级页面的依赖注入。
library;

import 'package:get/get.dart';

import '../contacts/contacts_controller.dart';
import '../conversations/conversations_controller.dart';
import '../mine/mine_controller.dart';
import 'main_navigation_controller.dart';

class MainNavigationBinding extends Bindings {
  MainNavigationBinding(this.initialTab);

  final MainTab initialTab;

  @override
  void dependencies() {
    Get.lazyPut<MainNavigationController>(
      () => MainNavigationController(initialTab: initialTab),
    );
    Get.lazyPut<ConversationsController>(ConversationsController.new);
    Get.lazyPut<ContactsController>(ContactsController.new);
    Get.lazyPut<MineController>(MineController.new);
  }
}

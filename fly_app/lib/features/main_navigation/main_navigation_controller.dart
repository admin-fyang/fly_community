/// 登录后主导航状态。
///
/// 三个一级页签共用同一导航外壳；页签首次打开后保留实例，
/// 避免切换时丢失列表滚动位置和搜索状态。
library;

import 'dart:async';

import 'package:get/get.dart';

import '../../data/enums/top_bar_mode.dart';
import '../contacts/contacts_controller.dart';
import '../notifications/notification_unread_controller.dart';

enum MainTab { conversations, contacts, mine }

class MainNavigationController extends GetxController {
  MainNavigationController({required MainTab initialTab})
    : selectedTab = initialTab.obs;

  final Rx<MainTab> selectedTab;
  final loadedTabs = <MainTab>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadedTabs.add(selectedTab.value);
  }

  void select(MainTab tab) {
    // 重复点击保留按钮反馈，但不重复加载或刷新。
    if (selectedTab.value == tab) return;
    loadedTabs.add(tab);
    selectedTab.value = tab;
    if (tab == MainTab.conversations) {
      unawaited(Get.find<NotificationUnreadController>().refreshCount());
    }
  }

  void handleBlockedBack() {
    if (selectedTab.value == MainTab.contacts &&
        Get.isRegistered<ContactsController>()) {
      final contacts = Get.find<ContactsController>();
      if (contacts.topBarMode.value == TopBarMode.search) {
        contacts.closeSearch();
        return;
      }
    }
    select(MainTab.conversations);
  }

}

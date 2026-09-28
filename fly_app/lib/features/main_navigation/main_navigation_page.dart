/// 登录后主页外壳：会话、通讯录、我的。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../contacts/contacts_page.dart';
import '../conversations/conversations_controller.dart';
import '../conversations/conversations_page.dart';
import '../mine/mine_page.dart';
import 'main_navigation_insets.dart';
import 'main_navigation_controller.dart';
import 'widgets/app_bottom_navigation_bar.dart';

class MainNavigationPage extends GetView<MainNavigationController> {
  const MainNavigationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Obx(() {
      final selected = controller.selectedTab.value;
      final loaded = controller.loadedTabs.toSet();
      final hideNavigation =
          keyboardVisible ||
          selected == MainTab.conversations &&
              Get.isRegistered<ConversationsController>() &&
              Get.find<ConversationsController>().isSelectionMode.value;
      return PopScope(
        canPop: selected == MainTab.conversations,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.handleBlockedBack();
        },
        child: Scaffold(
          // 子页自行处理键盘收缩，外壳不再次扣除键盘高度。
          resizeToAvoidBottomInset: false,
          body: MainNavigationInsets(
            bottom: hideNavigation
                ? 0
                : MainNavigationInsets.height +
                      MainNavigationInsets.gap +
                      safeBottom,
            child: Stack(
              fit: StackFit.expand,
              children: [
                IndexedStack(
                  index: selected.index,
                  children: [
                    loaded.contains(MainTab.conversations)
                        ? const ConversationsPage(
                            key: ValueKey('main-conversations'),
                          )
                        : const SizedBox.shrink(),
                    loaded.contains(MainTab.contacts)
                        ? const ContactsPage(
                            key: ValueKey('main-contacts'),
                            embeddedInMainShell: true,
                          )
                        : const SizedBox.shrink(),
                    loaded.contains(MainTab.mine)
                        ? const MinePage(key: ValueKey('main-mine'))
                        : const SizedBox.shrink(),
                  ],
                ),
                if (!hideNavigation)
                  Positioned(
                    left: MainNavigationInsets.horizontal,
                    right: MainNavigationInsets.horizontal,
                    bottom: safeBottom + MainNavigationInsets.gap,
                    child: AppBottomNavigationBar(
                      currentTab: selected,
                      onSelected: controller.select,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

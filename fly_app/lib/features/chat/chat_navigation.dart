/// 聊天路由协调器。
///
/// GetX 的聊天 Controller 按 conversation_id 标签注册；路由协调器负责确保
/// 导航栈只保留当前聊天，同时避免旧路由清理误删新会话实例。
library;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/models/conversation_model.dart';
import '../../routes/app_routes.dart';

/// 当前聊天路由的轻量会话标记。
///
/// 它是永久注册的轻量路由状态，不持有消息或 UI 资源。新页面先激活会话，
/// 旧页面销毁时按 conversation_id 条件清理，因此同路由替换不会互相覆盖。
class ChatRouteSession {
  ChatRouteSession(String conversationId) : _conversationId = conversationId;

  String _conversationId;

  String get conversationId => _conversationId;

  bool get hasActiveChat => _conversationId.isNotEmpty;

  /// 每个聊天控制器必须按会话隔离，避免同路由替换时复用旧实例。
  String get controllerTag => controllerTagFor(_conversationId);

  bool isControllerRegistered<T>() =>
      hasActiveChat && Get.isRegistered<T>(tag: controllerTag);

  T findController<T>() => Get.find<T>(tag: controllerTag);

  static String controllerTagFor(String conversationId) =>
      'chat:${conversationId.trim().isEmpty ? 'unresolved' : conversationId.trim()}';

  /// 新聊天 Binding 先激活新会话；旧页面稍后销毁时不能清掉新会话标记。
  void activate(String conversationId) {
    _conversationId = conversationId.trim();
  }

  void deactivate(String conversationId) {
    if (_conversationId == conversationId.trim()) _conversationId = '';
  }
}

class ChatNavigation {
  ChatNavigation._();

  /// 打开指定会话，并保证新路由不会复用另一个会话的 Controller。
  ///
  /// [replaceCurrentWhenNoChat] 用于用户资料页：资料页被聊天替换后，
  /// 旧 ProfileController 会释放，从聊天再打开其他用户资料时不会串资料。
  static Future<void> open(
    ConversationModel conversation, {
    bool replaceCurrentWhenNoChat = false,
  }) async {
    final route = AppRoutes.chatFor(conversation.id);
    if (!Get.isRegistered<ChatRouteSession>() ||
        !Get.find<ChatRouteSession>().hasActiveChat) {
      if (replaceCurrentWhenNoChat) {
        await Get.offNamed<void>(route, arguments: conversation);
      } else {
        await Get.toNamed<void>(route, arguments: conversation);
      }
      return;
    }

    final activeConversationId = Get.find<ChatRouteSession>().conversationId;
    if (activeConversationId == conversation.id) {
      Get.until(_isChatRoute);
      return;
    }

    // 先回到旧聊天，再由 GetX 的路由替换原语完成旧依赖销毁与新
    // Binding 创建。手工“先弹出旧聊天再压入新聊天”会与 GetX 的
    // 延迟路由清理竞态，可能把刚创建的新 Controller 误删。
    Get.until(_isChatRoute);
    await Get.offNamed<void>(route, arguments: conversation);
  }

  static bool _isChatRoute(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return false;
    return (Uri.tryParse(name)?.path ?? name) == AppRoutes.chat;
  }
}

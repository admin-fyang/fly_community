/// 聊天页依赖注入。
///
/// 进入聊天详情页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import '../../data/models/conversation_model.dart';
import 'chat_controller.dart';
import 'chat_navigation.dart';

class ChatBinding extends Bindings {
  @override
  void dependencies() {
    final arguments = Get.arguments;
    final argumentConversationId = arguments is ConversationModel
        ? arguments.id.trim()
        : '';
    final routeConversationId =
        Uri.tryParse(
          Get.currentRoute,
        )?.queryParameters['conversation_id']?.trim() ??
        '';
    // 立即注册而不使用 lazyPut：后续资料页发起导航时 Get.arguments
    // 已经变成资料页参数，延迟创建会丢失原聊天 conversation_id。
    final conversationId = argumentConversationId.isNotEmpty
        ? argumentConversationId
        : routeConversationId;
    final session = Get.isRegistered<ChatRouteSession>()
        ? Get.find<ChatRouteSession>()
        : Get.put<ChatRouteSession>(
            ChatRouteSession(conversationId),
            permanent: true,
          );
    session.activate(conversationId);

    // 同一路由从聊天 A 替换到聊天 B 时，旧路由会在新页面构建后才清理依赖。
    // 按 conversation_id 加标签，确保旧路由只能销毁 A，不能复用或误删 B。
    Get.lazyPut<ChatController>(
      () => ChatController(),
      tag: ChatRouteSession.controllerTagFor(conversationId),
    );
  }
}

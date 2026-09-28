library;

import '../../data/models/conversation_model.dart';
import '../../data/models/conversation_projection_change.dart';
import '../../data/models/im_api_models.dart';
import '../../data/models/message_model.dart';
import '../../data/enums/conversation_type.dart';

/// 清空或删除会话时的二选一定位参数。
///
/// 构造函数只允许“会话 ID”或“类型 + 对象 ID”之一，防止客户端发出混传协议。
class ConversationLocator {
  const ConversationLocator.byId(String conversationId)
    : this._(conversationId: conversationId);

  const ConversationLocator.byObject({
    required ConversationType type,
    required String objectId,
  }) : this._(type: type, objectId: objectId);

  const ConversationLocator._({this.conversationId, this.type, this.objectId});

  final String? conversationId;
  final ConversationType? type;
  final String? objectId;

  Map<String, dynamic> toJson() {
    final id = conversationId?.trim() ?? '';
    final target = objectId?.trim() ?? '';
    if (id.isNotEmpty && type == null && target.isEmpty) {
      return {'conversation_id': id};
    }
    if (id.isEmpty && type != null && target.isNotEmpty) {
      return {
        'conversation_type': type!.name,
        'conversation_object_id': target,
      };
    }
    throw StateError('会话定位参数必须且只能选择一种方式');
  }
}

/// 批量会话操作中的单条失败信息。
///
/// 服务端允许各会话独立提交，因此失败详情必须保留下来，供页面准确提示并仅保留
/// 失败项的选择状态。字段解析兼容 `conversation_id` 与通用 `id`。
class ConversationBatchFailure {
  const ConversationBatchFailure({required this.conversationId, this.message});

  final String conversationId;
  final String? message;
}

/// 批量会话操作结果。
///
/// 幂等项代表目标状态已经满足，与本次实际变更项一样都属于成功，客户端必须同步
/// 更新本地投影，不能把它误报为失败。
class ConversationBatchResult {
  const ConversationBatchResult({
    required this.requestedCount,
    required this.succeededIds,
    required this.idempotentIds,
    required this.failedItems,
  });

  final int requestedCount;
  final List<String> succeededIds;
  final List<String> idempotentIds;
  final List<ConversationBatchFailure> failedItems;

  Set<String> get successfulIds => {...succeededIds, ...idempotentIds};
}

abstract interface class ImRepository {
  /// 只发布已经成功提交到 SQLite 的完整会话投影。
  Stream<ConversationProjectionChange> watchConversationChanges();

  Future<ImConversationPage> getConversations({
    int limit = 20,
    int? beforeUpdateTime,
    String? beforeConversationId,
  });

  Future<List<ConversationModel>> getCachedConversations({int limit = 200});

  /// 按目标用户幂等获取或创建单聊会话。
  Future<ConversationModel> resolveSingleConversation(String targetUserId);

  /// 按群 ID 幂等取得或恢复当前用户的群会话投影。

  Future<CentrifugoConnectionToken> getCentrifugoToken();

  Future<ImHistoryPage> getMessages({
    required String conversationId,
    int limit = 30,
    String? beforeSeq,
  });

  Future<List<MessageModel>> getCachedMessages({
    required String conversationId,
    int limit = 30,
    String? beforeSeq,
  });

  Future<MessageModel> sendText({
    required String conversationId,
    required String clientMsgId,
    required String bodyText,
    String? replyMessageId,
  });

  Future<MessageModel> sendRichMessage({
    required String conversationId,
    required String clientMsgId,
    required String messageType,
    List<MessageAttachmentDto> attachments,
    String? replyMessageId,
  });

  Future<ImSyncResult> sync({
    required String cursor,
    required String deviceId,
    int limit = 200,
  });

  /// 上报不包含消息正文和凭证的 IM 协议兼容性摘要。
  Future<void> reportProtocolIssue({
    required String event,
    required String clientVersion,
    required String platform,
    required String protocolVersion,
    required Map<String, String> context,
  });

  Future<void> markRead({required String conversationId, required int seq});

  Future<MessageModel> recallMessage({
    required String messageId,
    String reason = '用户主动撤回',
  });

  Future<void> deleteMessageForMe(String messageId);

  Future<void> clearConversationMessages(ConversationLocator locator);

  Future<void> deleteConversation(ConversationLocator locator);

  Future<void> updateConversationMuted({
    required String conversationId,
    required bool isMuted,
  });

  Future<ConversationBatchResult> clearConversations(
    List<String> conversationIds,
  );

  Future<ConversationBatchResult> deleteConversations(
    List<String> conversationIds,
  );

  Future<ConversationBatchResult> updateConversationsMuted({
    required List<String> conversationIds,
    required bool isMuted,
  });

  Future<ConversationBatchResult> updateConversationsPinned({
    required List<String> conversationIds,
    required bool isPinned,
  });
}

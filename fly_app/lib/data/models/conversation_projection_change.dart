/// SQLite 会话投影提交后的变化通知。
library;

import 'conversation_model.dart';

class ConversationProjectionChange {
  ConversationProjectionChange.upsert(ConversationModel value)
    : conversation = value,
      conversationId = value.id,
      isDeleted = false;

  const ConversationProjectionChange.deleted(this.conversationId)
    : conversation = null,
      isDeleted = true;

  final String conversationId;
  final ConversationModel? conversation;
  final bool isDeleted;
}

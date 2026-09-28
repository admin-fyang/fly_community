/// 聊天页当前登录周期内的消息窗口缓存。
///
/// 该缓存只驻留内存，不写入 SQLite。它保存控制器销毁前已经加载的消息窗口，
/// 避免返回会话时重复请求已加载的历史分页。它不保存像素偏移、可见消息
/// 或是否位于底部等任何位置信息。缓存键同时包含用户与会话，杜绝账号间串数据。
library;

import '../models/message_model.dart';

/// 一次聊天页离开时的完整视口快照。
class ChatViewportSnapshot {
  const ChatViewportSnapshot({
    required this.messages,
    required this.lastLoadedSeq,
    required this.nextBeforeSeq,
    required this.hasMoreMessages,
  });

  /// 离开页面时已经加载的消息窗口。
  final List<MessageModel> messages;

  final int lastLoadedSeq;
  final String? nextBeforeSeq;
  final bool hasMoreMessages;
}

/// 账号隔离的聊天页视口内存缓存。
class ChatViewportStateStore {
  final Map<String, ChatViewportSnapshot> _snapshots = {};

  String _key(String userId, String conversationId) =>
      '$userId:$conversationId';

  ChatViewportSnapshot? read({
    required String userId,
    required String conversationId,
  }) => _snapshots[_key(userId, conversationId)];

  void save({
    required String userId,
    required String conversationId,
    required ChatViewportSnapshot snapshot,
  }) {
    _snapshots[_key(userId, conversationId)] = snapshot;
  }

  /// 退出登录或凭证失效时清空，既释放消息窗口内存，也避免旧会话被再次恢复。
  void clear() {
    _snapshots.clear();
  }
}

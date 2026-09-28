/// 会话模型。
///
/// 会话列表项的数据来源,字段覆盖 UI 所需的全部状态:置顶、静音、未读、
/// 群聊发送者前缀、媒体消息预览等。第一阶段由 Mock 驱动。
library;

import '../enums/conversation_type.dart';
import '../enums/message_type.dart';
import 'message_model.dart';

/// 会话模型（会话列表项的数据来源）
///
/// 第一阶段由 Mock 驱动，字段覆盖 UI 需要的所有状态：
/// 置顶、静音、未读、群聊发送者前缀、媒体消息预览等。
class ConversationModel {
  const ConversationModel({
    required this.id,
    required this.type,
    required this.title,
    this.searchName,
    this.searchIdentifier,
    this.peerUserId,
    this.avatarUrl,
    required this.lastMessageType,
    this.lastMessageText = '',
    this.lastSenderName,
    this.lastReply,
    this.lastMessageIsMine = false,
    this.lastMessageId,
    this.lastSeq = 0,
    required this.time,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
  });

  final String id;
  final ConversationType type;
  final String title;

  /// 搜索元数据从本地权威用户/群目录填充，不影响会话标题和备注展示。
  final String? searchName;
  final String? searchIdentifier;
  final String? peerUserId;
  final String? avatarUrl;

  /// 最后一条消息类型，决定预览是否走「图标 + 类型名」高亮
  final MessageType lastMessageType;

  /// 最后一条消息正文（文本消息用）
  final String lastMessageText;

  /// 群聊预览前缀，如「风」「Combot」；单聊为空
  final String? lastSenderName;

  /// 最后一条消息携带的引用快照，用于会话列表独立展示引用摘要。
  ///
  /// 该字段直接消费服务端 `last_message.reply`，不得依赖原消息已加载。
  final ReplyQuote? lastReply;
  final bool lastMessageIsMine;
  final String? lastMessageId;

  /// 会话最新消息序号，用于 SQLite 增量快照和未读水位。
  final int lastSeq;

  final DateTime time;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;

  /// 是否有未读消息
  bool get hasUnread => unreadCount > 0;

  /// 预览是否为媒体类消息(决定预览用图标+类型名而非纯文本)
  bool get isMediaPreview => lastMessageType.isMedia;

  /// 清空聊天后保留会话与个人设置，只移除旧消息预览和未读状态。
  ///
  /// 独立方法用于显式把可空的 `lastMessageId` 设为 null，避免普通 `copyWith`
  /// 将 null 解释为“保持原值”，导致清空后仍残留旧消息标识。
  ConversationModel clearMessagePreview() {
    return ConversationModel(
      id: id,
      type: type,
      title: title,
      searchName: searchName,
      searchIdentifier: searchIdentifier,
      peerUserId: peerUserId,
      avatarUrl: avatarUrl,
      lastMessageType: MessageType.text,
      lastMessageText: '',
      lastReply: null,
      lastMessageIsMine: false,
      lastMessageId: null,
      lastSeq: lastSeq,
      time: time,
      unreadCount: 0,
      isPinned: isPinned,
      isMuted: isMuted,
    );
  }

  /// 用一条确定的最新消息替换会话预览。
  ///
  /// 与普通 [copyWith] 不同，本方法允许把上一条消息的引用快照明确清空；
  /// 否则“引用消息之后发送普通消息”时会错误残留旧引用。
  ConversationModel replaceLastMessage({
    required MessageType type,
    required String text,
    required DateTime time,
    required String messageId,
    required int lastSeq,
    String? senderName,
    ReplyQuote? reply,
    bool? messageIsMine,
    int? unreadCount,
  }) {
    return ConversationModel(
      id: id,
      type: this.type,
      title: title,
      searchName: searchName,
      searchIdentifier: searchIdentifier,
      peerUserId: peerUserId,
      avatarUrl: avatarUrl,
      lastMessageType: type,
      lastMessageText: text,
      lastSenderName: senderName,
      lastReply: reply,
      lastMessageIsMine: messageIsMine ?? false,
      lastMessageId: messageId,
      lastSeq: lastSeq,
      time: time,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned,
      isMuted: isMuted,
    );
  }

  ConversationModel copyWith({
    String? title,
    String? searchName,
    String? searchIdentifier,
    String? peerUserId,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    MessageType? lastMessageType,
    String? lastMessageText,
    String? lastSenderName,
    ReplyQuote? lastReply,
    bool? lastMessageIsMine,
    String? lastMessageId,
    int? lastSeq,
    DateTime? time,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
  }) {
    return ConversationModel(
      id: id,
      type: type,
      title: title ?? this.title,
      searchName: searchName ?? this.searchName,
      searchIdentifier: searchIdentifier ?? this.searchIdentifier,
      peerUserId: peerUserId ?? this.peerUserId,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      lastReply: lastReply ?? this.lastReply,
      lastMessageIsMine: lastMessageIsMine ?? this.lastMessageIsMine,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastSeq: lastSeq ?? this.lastSeq,
      time: time ?? this.time,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

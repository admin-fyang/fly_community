/// IM UI 模型与 SQLite 快照 JSON 的双向转换。
///
/// 可查询、排序和幂等所需的核心字段仍保存在独立列中；
/// 快照只承载 UI 完整恢复所需的富消息展示数据。
library;

import 'dart:convert';

import '../enums/conversation_type.dart';
import '../enums/message_status.dart';
import '../enums/message_type.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

String encodeLocalMessage(MessageModel message) => jsonEncode({
  'id': message.id,
  'type': message.type.name,
  'conversation_id': message.conversationId,
  'client_msg_id': message.clientMsgId,
  'seq': message.seq,
  'is_mine': message.isMine,
  'time': message.time.millisecondsSinceEpoch,
  'sender_id': message.senderId,
  'sender_name': message.senderName,
  'sender_avatar_url': message.senderAvatarUrl,
  'text': message.text,
  'send_status': message.status.name,
  'send_error': message.sendError,
  'image_url': message.imageUrl,
  'attachments': message.attachments.map(_encodeMessageAttachment).toList(),
  if (message.reply != null)
    'reply': {
      'snapshot_version': message.reply!.snapshotVersion,
      'message_id': message.reply!.messageId,
      'seq': message.reply!.seq,
      'sender_id': message.reply!.senderId,
      'sender_name': message.reply!.senderName,
      'message_type': message.reply!.messageType.name,
      'is_available': message.reply!.isAvailable,
      'unavailable_reason': message.reply!.unavailableReason,
      'summary': message.reply!.summary,
      'attachment_count': message.reply!.attachmentCount,
      if (message.reply!.preview != null)
        'preview': _encodeReplyPreview(message.reply!.preview!),
    },
  'file_name': message.fileName,
  'file_meta': message.fileMeta,
});

MessageModel? decodeLocalMessage(Object? raw) {
  try {
    final json = _jsonObject(jsonDecode(raw?.toString() ?? ''));
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final reply = _jsonObject(json['reply']);
    return MessageModel(
      id: id,
      type: _messageType(json['type']?.toString()),
      conversationId: json['conversation_id']?.toString(),
      clientMsgId: json['client_msg_id']?.toString(),
      seq: _int(json['seq']),
      isMine: json['is_mine'] == true,
      time: DateTime.fromMillisecondsSinceEpoch(_int(json['time']) ?? 0),
      senderId: json['sender_id']?.toString(),
      senderName: json['sender_name']?.toString(),
      senderAvatarUrl: json['sender_avatar_url']?.toString(),
      text: json['text']?.toString() ?? '',
      status: _messageStatus(json['send_status']?.toString()),
      sendError: json['send_error']?.toString(),
      imageUrl: json['image_url']?.toString(),
      attachments:
          (json['attachments'] is List ? json['attachments'] as List : const [])
              .whereType<Map>()
              .map((item) => _decodeMessageAttachment(_jsonObject(item)))
              .toList(),
      reply: reply.isEmpty
          ? null
          : ReplyQuote(
              snapshotVersion: _int(reply['snapshot_version']) ?? 1,
              messageId: reply['message_id']?.toString(),
              seq: _int(reply['seq']),
              senderId: reply['sender_id']?.toString(),
              senderName: reply['sender_name']?.toString() ?? '',
              messageType: _messageType(reply['message_type']?.toString()),
              isAvailable: reply['is_available'] != false,
              unavailableReason: reply['unavailable_reason']?.toString(),
              summary:
                  reply['summary']?.toString() ??
                  reply['text']?.toString() ??
                  '',
              preview: _decodeReplyPreview(reply['preview']),
              attachmentCount: _int(reply['attachment_count']) ?? 0,
            ),
      fileName: json['file_name']?.toString(),
      fileMeta: json['file_meta']?.toString(),
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _encodeMessageAttachment(MessageAttachment item) => {
  'resource_id': item.resourceId,
  'resource_url': item.resourceUrl,
  'thumbnail_resource_id': item.thumbnailResourceId,
  'thumbnail_url': item.thumbnailUrl,
  'file_name': item.fileName,
  'file_size': item.fileSize,
  'mime_type': item.mimeType,
  'duration_ms': item.durationMs,
  'width': item.width,
  'height': item.height,
  'waveform': item.waveform,
  'local_preview_path': item.localPreviewPath,
  // 选择器路径可能是短生命周期 URI/Blob URL，不能写入 SQLite。刷新恢复时
  // 必须以 local_pending_attachment 中的应用私有副本为准。
};

MessageAttachment _decodeMessageAttachment(Map<String, dynamic> json) =>
    MessageAttachment(
      resourceId: json['resource_id']?.toString() ?? '',
      resourceUrl: json['resource_url']?.toString(),
      thumbnailResourceId: json['thumbnail_resource_id']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      fileName: json['file_name']?.toString(),
      fileSize: _int(json['file_size']),
      mimeType: json['mime_type']?.toString(),
      durationMs: _int(json['duration_ms']),
      width: _int(json['width']),
      height: _int(json['height']),
      waveform: (json['waveform'] is List ? json['waveform'] as List : const [])
          .whereType<num>()
          .map((value) => value.toDouble().clamp(0.0, 1.0))
          .toList(growable: false),
      localPreviewPath: json['local_preview_path']?.toString(),
      localMediaPath: json['local_media_path']?.toString(),
    );

Map<String, Object?> _encodeReplyPreview(ReplyPreview preview) => {
  'kind': preview.kind.name,
  'resource_id': preview.resourceId,
  'thumbnail_resource_id': preview.thumbnailResourceId,
  'preview_url': preview.previewUrl,
  'width': preview.width,
  'height': preview.height,
  'duration_ms': preview.durationMs,
  'file_name': preview.fileName,
  'file_size': preview.fileSize,
  'mime_type': preview.mimeType,
  'name': preview.name,
  'address': preview.address,
  'shared_user_id': preview.sharedUserId,
  'display_name': preview.displayName,
  'avatar_url': preview.avatarUrl,
};

ReplyPreview? _decodeReplyPreview(Object? raw) {
  final json = _jsonObject(raw);
  if (json.isEmpty) return null;
  return ReplyPreview(
    kind: _messageType(json['kind']?.toString()),
    resourceId: json['resource_id']?.toString(),
    thumbnailResourceId: json['thumbnail_resource_id']?.toString(),
    previewUrl: json['preview_url']?.toString(),
    width: _int(json['width']),
    height: _int(json['height']),
    durationMs: _int(json['duration_ms']),
    fileName: json['file_name']?.toString(),
    fileSize: _int(json['file_size']),
    mimeType: json['mime_type']?.toString(),
    name: json['name']?.toString(),
    address: json['address']?.toString(),
    sharedUserId: json['shared_user_id']?.toString(),
    displayName: json['display_name']?.toString(),
    avatarUrl: json['avatar_url']?.toString(),
  );
}

String encodeLocalConversation(ConversationModel conversation) => jsonEncode({
  'id': conversation.id,
  'type': conversation.type.name,
  'title': conversation.title,
  'peer_user_id': conversation.peerUserId,
  'avatar_url': conversation.avatarUrl,
  'last_message_type': conversation.lastMessageType.name,
  'last_message_text': conversation.lastMessageText,
  'last_sender_name': conversation.lastSenderName,
  if (conversation.lastReply != null)
    'last_reply': _encodeReply(conversation.lastReply!),
  'last_message_is_mine': conversation.lastMessageIsMine,
  'last_message_id': conversation.lastMessageId,
  'last_seq': conversation.lastSeq,
  'time': conversation.time.millisecondsSinceEpoch,
  'unread_count': conversation.unreadCount,
  'is_pinned': conversation.isPinned,
  'is_muted': conversation.isMuted,
});

ConversationModel? decodeLocalConversation(Object? raw) {
  try {
    final json = _jsonObject(jsonDecode(raw?.toString() ?? ''));
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return ConversationModel(
      id: id,
      type: ConversationType.single,
      title: json['title']?.toString() ?? '会话',
      peerUserId: json['peer_user_id']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      lastMessageType: _messageType(json['last_message_type']?.toString()),
      lastMessageText: json['last_message_text']?.toString() ?? '',
      lastSenderName: json['last_sender_name']?.toString(),
      lastReply: _decodeReply(json['last_reply']),
      lastMessageIsMine: json['last_message_is_mine'] == true,
      lastMessageId: json['last_message_id']?.toString(),
      lastSeq: _int(json['last_seq']) ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch(_int(json['time']) ?? 0),
      unreadCount: _int(json['unread_count']) ?? 0,
      isPinned: json['is_pinned'] == true,
      isMuted: json['is_muted'] == true,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _encodeReply(ReplyQuote reply) => {
  'snapshot_version': reply.snapshotVersion,
  'message_id': reply.messageId,
  'seq': reply.seq,
  'sender_id': reply.senderId,
  'sender_name': reply.senderName,
  'message_type': reply.messageType.name,
  'is_available': reply.isAvailable,
  'unavailable_reason': reply.unavailableReason,
  'summary': reply.summary,
  'attachment_count': reply.attachmentCount,
  if (reply.preview != null) 'preview': _encodeReplyPreview(reply.preview!),
};

ReplyQuote? _decodeReply(Object? raw) {
  final reply = _jsonObject(raw);
  if (reply.isEmpty) return null;
  return ReplyQuote(
    snapshotVersion: _int(reply['snapshot_version']) ?? 1,
    messageId: reply['message_id']?.toString(),
    seq: _int(reply['seq']),
    senderId: reply['sender_id']?.toString(),
    senderName: reply['sender_name']?.toString() ?? '',
    messageType: _messageType(reply['message_type']?.toString()),
    isAvailable: reply['is_available'] != false,
    unavailableReason: reply['unavailable_reason']?.toString(),
    summary: reply['summary']?.toString() ?? reply['text']?.toString() ?? '',
    preview: _decodeReplyPreview(reply['preview']),
    attachmentCount: _int(reply['attachment_count']) ?? 0,
  );
}

MessageType _messageType(String? value) {
  for (final type in MessageType.values) {
    if (type.name == value) return type;
  }
  return MessageType.text;
}

MessageStatus _messageStatus(String? value) {
  for (final status in MessageStatus.values) {
    if (status.name == value) return status;
  }
  return MessageStatus.sent;
}

Map<String, dynamic> _jsonObject(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

int? _int(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

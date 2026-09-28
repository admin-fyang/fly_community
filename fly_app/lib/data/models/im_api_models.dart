/// IM 接口 DTO 与 UI 模型转换。
///
/// 服务端字段在这里收口，页面和 Controller 不直接解析后端 JSON。
library;

import '../enums/conversation_type.dart';
import '../enums/message_status.dart';
import '../enums/message_type.dart';
import 'conversation_model.dart';
import 'message_model.dart';

/// Centrifugo 短期连接凭证。WebSocket 地址和刷新时间均以服务端响应为准。
class CentrifugoConnectionToken {
  const CentrifugoConnectionToken({
    required this.token,
    required this.tokenType,
    required this.websocketUrl,
    required this.channel,
    required this.subscriptionMode,
    required this.expiresAt,
    required this.expiresIn,
    required this.refreshAfter,
    this.authenticationMode = 'jwt',
  });

  final String token;
  final String tokenType;
  final String websocketUrl;
  final String channel;
  final String subscriptionMode;
  final int expiresAt;
  final int expiresIn;
  final int refreshAfter;

  /// proxy 由后端逐次校验登录会话；缺省 jwt 保持旧服务部署兼容。
  final String authenticationMode;

  /// 用户私有频道由后端、JWT、Outbox 和 Centrifugo namespace 共同约定。
  /// 只接受正整数用户 ID，避免配置错误被带入实时连接层后才暴露。
  static final RegExp _channelPattern = RegExp(r'^private-user:[1-9]\d*$');

  factory CentrifugoConnectionToken.fromJson(Map<String, dynamic> json) {
    final token = _string(json['token']) ?? '';
    final tokenType = _string(json['token_type']) ?? '';
    // 只有旧服务完全缺少字段时兼容 jwt；显式 null、对象或未知值均为协议错误。
    final authenticationMode = json.containsKey('authentication_mode')
        ? json['authentication_mode'] : 'jwt';
    if (authenticationMode is! String ||
        !const ['jwt', 'proxy'].contains(authenticationMode)) {
      throw const FormatException('Centrifugo 鉴权模式不受支持');
    }
    final websocketUrl = _string(json['websocket_url']) ?? '';
    final channel = _string(json['channel']) ?? '';
    final subscriptionMode = _string(json['subscription_mode']) ?? '';
    final expiresAt = _int(json['expires_at']) ?? 0;
    final expiresIn = _int(json['expires_in']) ?? 0;
    final refreshAfter = _int(json['refresh_after']) ?? 0;
    final websocketUri = Uri.tryParse(websocketUrl);
    final validWebsocketUrl =
        websocketUri != null &&
        websocketUri.hasAuthority &&
        (websocketUri.scheme == 'ws' || websocketUri.scheme == 'wss');
    if (token.isEmpty ||
        tokenType != 'centrifugo_connection' ||
        !validWebsocketUrl ||
        !_channelPattern.hasMatch(channel) ||
        subscriptionMode != 'server_side' ||
        expiresAt <= 0 ||
        expiresIn <= 0 ||
        refreshAfter <= 0 ||
        refreshAfter > expiresAt) {
      throw const FormatException('Centrifugo 连接凭证格式不正确');
    }
    return CentrifugoConnectionToken(
      token: token,
      tokenType: tokenType,
      websocketUrl: websocketUrl,
      channel: channel,
      subscriptionMode: subscriptionMode,
      expiresAt: expiresAt,
      expiresIn: expiresIn,
      refreshAfter: refreshAfter,
      authenticationMode: authenticationMode,
    );
  }
}

class ImSendResult {
  const ImSendResult({required this.message});

  final MessageModel message;

  factory ImSendResult.fromJson(
    Map<String, dynamic> json, {
    required String? currentUserId,
  }) {
    final raw = json['message'] is Map ? json['message'] : json;
    return ImSendResult(
      message: ImMessageDto.fromJson(
        _jsonObject(raw),
      ).toUiModel(currentUserId: currentUserId),
    );
  }
}

class ImHistoryPage {
  const ImHistoryPage({
    required this.items,
    required this.nextBeforeSeq,
    required this.hasMore,
    this.readState,
  });

  final List<MessageModel> items;
  final String? nextBeforeSeq;
  final bool hasMore;
  final ImReadState? readState;

  factory ImHistoryPage.fromJson(
    Map<String, dynamic> json, {
    required String? currentUserId,
    required int pageSize,
  }) {
    final rawItems = _jsonList(json['items'] ?? json['messages']);
    final nextBeforeSeq = _string(
      json['next_cursor'] ??
          json['next_before_message_id'] ??
          json['next_before_seq'],
    );
    return ImHistoryPage(
      items: rawItems
          .map(
            (item) => ImMessageDto.fromJson(
              _jsonObject(item),
            ).toUiModel(currentUserId: currentUserId),
          )
          .toList(),
      nextBeforeSeq: nextBeforeSeq,
      hasMore: rawItems.length >= pageSize && nextBeforeSeq != null,
      readState: ImReadState.tryFromJson(json['read_state']),
    );
  }
}

/// 会话中一个成员的已读游标快照。
class ImReadCursor {
  const ImReadCursor({required this.userId, required this.lastReadSeq});

  final String userId;
  final int lastReadSeq;

  factory ImReadCursor.fromJson(Map<String, dynamic> json) {
    final userId = _string(json['user_id']) ?? '';
    final lastReadSeq = _int(json['last_read_seq']);
    if (userId.isEmpty || lastReadSeq == null || lastReadSeq < 0) {
      throw const FormatException('IM 已读游标快照格式不正确');
    }
    return ImReadCursor(userId: userId, lastReadSeq: lastReadSeq);
  }
}

/// 会话已读状态快照。
///
/// 单聊同时包含 [self] 与 [peer]；群聊没有唯一对端，因此后端固定返回
/// `peer: null`。群聊已读人数未进入当前 UI，客户端只持久化自身游标。
class ImReadState {
  const ImReadState({required this.self, required this.peer});

  final ImReadCursor self;
  final ImReadCursor? peer;

  static ImReadState? tryFromJson(Object? value) {
    if (value == null) return null;
    final json = _jsonObject(value);
    if (json.isEmpty) return null;
    return ImReadState(
      self: ImReadCursor.fromJson(_jsonObject(json['self'])),
      peer: json['peer'] == null
          ? null
          : ImReadCursor.fromJson(_jsonObject(json['peer'])),
    );
  }
}

/// `receipt_updated` 事件载荷。
///
/// 后端以会话成员维度维护单调游标，一个回执事件表示
/// [userId] 已经阅读到哪个 seq，而不是单条消息布尔值。
class ImReceiptUpdate {
  const ImReceiptUpdate({
    required this.conversationId,
    this.clientMsgId,
    required this.userId,
    required this.lastReadSeq,
    required this.unreadCount,
  });

  final String conversationId;
  final String? clientMsgId;
  final String userId;
  final int lastReadSeq;
  final int unreadCount;

  factory ImReceiptUpdate.fromEvent(Map<String, dynamic> event) {
    final payload = _jsonObject(event['payload']);
    final conversationId =
        _string(payload['conversation_id'] ?? event['conversation_id']) ?? '';
    final userId = _string(payload['user_id']) ?? '';
    final lastReadSeq = _int(payload['last_read_seq']) ?? 0;
    final unreadCount = _int(payload['unread_count']) ?? 0;
    if (conversationId.isEmpty || userId.isEmpty) {
      throw const FormatException('IM 回执事件缺少会话或用户 ID');
    }
    if (lastReadSeq < 0) {
      throw const FormatException('IM 回执游标格式不正确');
    }
    return ImReceiptUpdate(
      conversationId: conversationId,
      userId: userId,
      lastReadSeq: lastReadSeq,
      unreadCount: unreadCount,
    );
  }
}

class ImConversationPage {
  const ImConversationPage({
    required this.items,
    required this.nextBeforeUpdateTime,
    required this.nextBeforeConversationId,
    required this.hasMore,
    this.readStates = const {},
  });

  final List<ConversationModel> items;
  final int? nextBeforeUpdateTime;
  final String? nextBeforeConversationId;
  final bool hasMore;
  final Map<String, ImReadState> readStates;

  factory ImConversationPage.fromJson(
    Map<String, dynamic> json, {
    required int pageSize,
    String? currentUserId,
  }) {
    final rawItems = _jsonList(json['items'] ?? json['conversations']);
    final nextBeforeUpdateTime = _int(json['next_before_update_time']);
    final nextBeforeConversationId = _string(
      json['next_before_conversation_id'] ?? json['next_cursor'],
    );
    final items = <ConversationModel>[];
    final readStates = <String, ImReadState>{};
    for (final item in rawItems) {
      final json = _jsonObject(item);
      final conversation = ImConversationDto.fromJson({
        ...json,
        '_current_user_id': currentUserId,
      }).toUiModel();
      items.add(conversation);
      final readState = ImReadState.tryFromJson(json['read_state']);
      if (readState != null) readStates[conversation.id] = readState;
    }
    return ImConversationPage(
      items: items,
      nextBeforeUpdateTime: nextBeforeUpdateTime,
      nextBeforeConversationId: nextBeforeConversationId,
      readStates: readStates,
      hasMore:
          rawItems.length >= pageSize &&
          nextBeforeUpdateTime != null &&
          nextBeforeConversationId != null,
    );
  }
}

class ImSyncResult {
  const ImSyncResult({
    required this.nextCursor,
    required this.events,
    required this.messages,
    this.hasMore = false,
  });

  final String nextCursor;

  /// 与 Centrifugo publication.data 完全一致的原始事件信封。
  final List<Map<String, dynamic>> events;
  final List<MessageModel> messages;
  final bool hasMore;

  factory ImSyncResult.fromJson(
    Map<String, dynamic> json, {
    required String? currentUserId,
  }) {
    final rawEvents = _jsonList(json['events'] ?? json['items']);
    final messages = <MessageModel>[];
    final events = <Map<String, dynamic>>[];
    for (final event in rawEvents) {
      final obj = _jsonObject(event);
      events.add(obj);
      final payload = obj['payload'];
      final rawMessage =
          obj['message'] ??
          (payload is Map ? payload['message'] : null) ??
          obj['data'];
      if (rawMessage is Map) {
        messages.add(
          ImMessageDto.fromJson(
            _jsonObject(rawMessage),
          ).toUiModel(currentUserId: currentUserId),
        );
      }
    }
    final nextCursor =
        _string(json['next_event_id'] ?? json['next_cursor'])?.trim() ?? '';
    if (nextCursor.isEmpty) {
      throw const FormatException('IM 同步响应缺少 next_cursor');
    }
    return ImSyncResult(
      nextCursor: nextCursor,
      events: events,
      messages: messages,
      hasMore: json['has_more'] == true,
    );
  }
}

class ImMessageDto {
  const ImMessageDto({
    required this.messageId,
    required this.conversationId,
    this.clientMsgId,
    required this.messageType,
    required this.senderId,
    required this.createdAt,
    required this.seq,
    this.senderName,
    this.senderAvatarUrl,
    this.bodyText = '',
    this.status,
    this.attachments = const [],
    this.reply,
  });

  final String messageId;
  final String conversationId;
  final String? clientMsgId;
  final MessageType messageType;
  final String senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final DateTime createdAt;
  final int? seq;
  final String bodyText;
  final String? status;
  final List<MessageAttachmentDto> attachments;
  final ReplyQuote? reply;

  factory ImMessageDto.fromJson(Map<String, dynamic> json) {
    final type = _messageType(_string(json['message_type']) ?? 'text');
    final sender = json['sender'] is Map
        ? _jsonObject(json['sender'])
        : const <String, dynamic>{};
    final attachments = _jsonList(json['attachments'])
        .whereType<Map>()
        .map((item) => MessageAttachmentDto.fromJson(_jsonObject(item)))
        .toList();
    return ImMessageDto(
      messageId: _string(json['message_id'] ?? json['id']) ?? '',
      conversationId: _string(json['conversation_id']) ?? '',
      clientMsgId: _string(json['client_msg_id']),
      messageType: type,
      senderId:
          _string(json['sender_id'] ?? json['from_user_id'] ?? sender['id']) ??
          '',
      senderName: _string(sender['name'] ?? json['sender_name']),
      senderAvatarUrl: _string(sender['avatar_url']),
      createdAt: _time(json['create_time'] ?? json['created_at']),
      seq: _int(json['seq']),
      bodyText:
          _string(json['body_text'] ?? json['content'] ?? json['text']) ?? '',
      status: _string(json['message_status'] ?? json['status']),
      attachments: attachments,
      reply: json['reply'] is Map
          ? _replyQuote(_jsonObject(json['reply']))
          : null,
    );
  }

  MessageModel toUiModel({required String? currentUserId}) {
    final mine = currentUserId != null && currentUserId == senderId;
    final firstAttachment = attachments.isEmpty ? null : attachments.first;
    return MessageModel(
      id: messageId,
      type: _statusIsRecall ? MessageType.recall : messageType,
      conversationId: conversationId,
      clientMsgId: clientMsgId,
      seq: seq,
      isMine: mine,
      time: createdAt,
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      text: _displayText(isMine: mine, currentUserId: currentUserId),
      // `message.status` 是正常、撤回、删除等服务端消息生命周期，不能
      // 当作已读回执。能够从历史或发送接口读取到的消息至少已经被
      // 服务端接收，因此先标记为 sent；后续只能由明确的回执数据升级状态。
      status: MessageStatus.sent,
      imageUrl:
          messageType == MessageType.image
          ? firstAttachment?.thumbnailUrl ?? firstAttachment?.url
          : null,
      attachments: attachments.map((item) => item.toUiAttachment()).toList(),
      reply: reply,
      fileName: firstAttachment?.filename,
      fileMeta: firstAttachment?.meta,
    );
  }

  bool get _statusIsRecall =>
      status == '20' || status == 'recalled' || status == 'recall';

  String _displayText({required bool isMine, required String? currentUserId}) {
    // 服务端撤回响应可能保留原 body_text。撤回生命周期必须优先于正文，
    // 避免客户端把被撤回内容继续展示在系统提示和会话预览中。
    if (_statusIsRecall || messageType == MessageType.recall) {
      return isMine ? '你撤回了一条消息' : '对方撤回了一条消息';
    }
    if (bodyText.isNotEmpty) return bodyText;
    return switch (messageType) {
      MessageType.image => '[图片]',
      MessageType.file => '[文件]',
      MessageType.system => bodyText,
      MessageType.recall => '消息已撤回',
      MessageType.text => '',
    };
  }
}

class ImConversationDto {
  const ImConversationDto({
    required this.conversationId,
    required this.type,
    required this.title,
    required this.updatedAt,
    required this.lastMessageType,
    this.peerUserId,
    this.avatarUrl,
    this.lastMessageText = '',
    this.lastSenderName,
    this.lastReply,
    this.lastMessageIsMine = false,
    this.lastMessageId,
    this.lastSeq = 0,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
  });

  final String conversationId;
  final ConversationType type;
  final String title;
  final String? peerUserId;
  final String? avatarUrl;
  final DateTime updatedAt;
  final MessageType lastMessageType;
  final String lastMessageText;
  final String? lastSenderName;
  final ReplyQuote? lastReply;
  final bool lastMessageIsMine;
  final String? lastMessageId;
  final int lastSeq;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;

  factory ImConversationDto.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'] is Map
        ? _jsonObject(json['last_message'])
        : json;
    final lastSender = last['sender'] is Map
        ? _jsonObject(last['sender'])
        : const <String, dynamic>{};
    final lastStatus = _string(last['message_status'] ?? last['status']);
    final lastType = _messageType(_string(last['message_type']) ?? 'text');
    final rawLastText =
        _string(
          last['body_text'] ?? last['content'] ?? json['last_message_text'],
        ) ??
        '';
    final currentUserId = _string(json['_current_user_id']);
    final lastSenderId = _string(
      last['sender_id'] ?? last['from_user_id'] ?? lastSender['id'],
    );
    final lastMessageIsMine =
        currentUserId != null &&
        currentUserId.isNotEmpty &&
        lastSenderId == currentUserId;
    return ImConversationDto(
      conversationId: _string(json['conversation_id'] ?? json['id']) ?? '',
      type: _conversationType(
        _string(json['conversation_type'] ?? json['type']),
      ),
      title:
          _string(json['title'] ?? json['name'] ?? json['peer_name']) ??
          '未命名会话',
      peerUserId: _string(
        json['peer_user_id'] ??
            json['recipient_user_id'] ??
            json['user_id'] ??
            json['target_id'],
      ),
      avatarUrl: _string(json['avatar_url'] ?? json['peer_avatar_url']),
      updatedAt: _time(
        json['update_time'] ?? json['updated_at'] ?? last['created_at'],
      ),
      lastMessageType: lastStatus == '20' ? MessageType.recall : lastType,
      lastMessageText: lastStatus == '20'
          ? '消息已撤回'
          : rawLastText,
      lastSenderName: _string(
        last['sender_name'] ?? lastSender['name'] ?? json['last_sender_name'],
      ),
      lastReply: last['reply'] is Map
          ? _replyQuote(_jsonObject(last['reply']))
          : null,
      lastMessageIsMine: lastMessageIsMine,
      lastMessageId: _string(json['last_message_id'] ?? last['message_id']),
      lastSeq: _int(json['last_seq']) ?? 0,
      unreadCount: _int(json['unread_count']) ?? 0,
      isPinned: json['is_pinned'] == true,
      isMuted: json['is_muted'] == true,
    );
  }

  ConversationModel toUiModel() => ConversationModel(
    id: conversationId,
    type: type,
    title: title,
    peerUserId: peerUserId,
    avatarUrl: avatarUrl,
    lastMessageType: lastMessageType,
    lastMessageText: lastMessageText,
    lastSenderName: lastSenderName,
    lastReply: lastReply,
    lastMessageIsMine: lastMessageIsMine,
    lastMessageId: lastMessageId,
    lastSeq: lastSeq,
    time: updatedAt,
    unreadCount: unreadCount,
    isPinned: isPinned,
    isMuted: isMuted,
  );
}

class MessageAttachmentDto {
  const MessageAttachmentDto({
    required this.resourceId,
    this.url,
    this.thumbnailResourceId,
    this.thumbnailUrl,
    this.filename,
    this.size,
    this.mimeType,
    this.durationMs,
    this.width,
    this.height,
    this.waveform = const [],
  });

  final String resourceId;
  final String? url;
  final String? thumbnailResourceId;
  final String? thumbnailUrl;
  final String? filename;
  final int? size;
  final String? mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final List<double> waveform;

  factory MessageAttachmentDto.fromJson(Map<String, dynamic> json) {
    return MessageAttachmentDto(
      resourceId: _string(json['resource_id']) ?? '',
      url: _string(json['url'] ?? json['file_url'] ?? json['resource_url']),
      thumbnailResourceId: _string(json['thumbnail_resource_id']),
      thumbnailUrl: _string(json['thumbnail_url']),
      filename: _string(json['filename'] ?? json['file_name']),
      size: _int(json['size'] ?? json['file_size']),
      mimeType: _string(json['mime_type'] ?? json['file_type']),
      durationMs: _int(json['duration_ms']),
      width: _int(json['width']),
      height: _int(json['height']),
      waveform: _jsonList(
        json['waveform'],
      ).map((item) => item is num ? item.toDouble() : 0.0).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'resource_id': resourceId,
    if (thumbnailResourceId != null)
      'thumbnail_resource_id': thumbnailResourceId,
    if (durationMs != null) 'duration_ms': durationMs,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (waveform.isNotEmpty) 'waveform': waveform,
  };

  MessageAttachment toUiAttachment() => MessageAttachment(
    resourceId: resourceId,
    resourceUrl: url,
    thumbnailResourceId: thumbnailResourceId,
    thumbnailUrl: thumbnailUrl,
    fileName: filename,
    fileSize: size,
    mimeType: mimeType,
    durationMs: durationMs,
    width: width,
    height: height,
    waveform: waveform,
  );

  String? get durationText {
    final ms = durationMs;
    if (ms == null) return null;
    final seconds = (ms / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String? get meta {
    final parts = <String>[];
    if (size != null) parts.add(_formatSize(size!));
    if (mimeType != null && mimeType!.isNotEmpty) parts.add(mimeType!);
    return parts.isEmpty ? null : parts.join(' • ');
  }
}

class MessageUploadCredential {
  const MessageUploadCredential({
    required this.resourceId,
    required this.uploadUrl,
    required this.headers,
    required this.expiresIn,
    required this.uploadMode,
    this.uploadId,
    this.partSize,
    this.totalParts,
    this.expiresAt,
  });

  final String resourceId;
  final String uploadUrl;
  final Map<String, String> headers;
  final int expiresIn;
  final String uploadMode;
  final String? uploadId;
  final int? partSize;
  final int? totalParts;
  final int? expiresAt;

  factory MessageUploadCredential.fromJson(Map<String, dynamic> json) {
    return MessageUploadCredential(
      resourceId: _string(json['resource_id']) ?? '',
      uploadUrl: _string(json['upload_url']) ?? '',
      headers: _stringMap(json['headers']),
      expiresIn: _int(json['expires_in']) ?? 0,
      uploadMode: _string(json['upload_mode']) ?? 'single',
      uploadId: _string(json['upload_id']),
      partSize: _int(json['part_size']),
      totalParts: _int(json['total_parts']),
      expiresAt: _int(json['expires_at']),
    );
  }
}

class MessageUploadFile {
  const MessageUploadFile({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  final String filename;
  final String mimeType;
  final List<int> bytes;

  int get size => bytes.length;
}

class CompletedMessageUpload {
  const CompletedMessageUpload({
    required this.resourceId,
    required this.url,
    required this.status,
  });

  final String resourceId;
  final String url;
  final String status;

  factory CompletedMessageUpload.fromJson(Map<String, dynamic> json) {
    return CompletedMessageUpload(
      resourceId: _string(json['resource_id']) ?? '',
      url: _string(json['url'] ?? json['resource_url']) ?? '',
      status: _string(json['status']) ?? '',
    );
  }
}

ReplyQuote _replyQuote(Map<String, dynamic> json) {
  final messageType = _messageType(_string(json['message_type']) ?? 'text');
  final available = json['is_available'] != false;
  final summary =
      _string(
        json['summary'] ?? json['body_text'] ?? json['text'] ?? json['content'],
      ) ??
      _replyFallback(messageType);
  return ReplyQuote(
    snapshotVersion: _int(json['snapshot_version']) ?? 1,
    messageId: _string(json['message_id']),
    seq: _int(json['seq']),
    senderId: _string(json['sender_id']),
    senderName: _string(json['sender_name']) ?? '',
    messageType: messageType,
    isAvailable: available,
    unavailableReason: _string(json['unavailable_reason']),
    summary: available ? summary : (_string(json['summary']) ?? '原消息已撤回'),
    preview: available && json['preview'] is Map
        ? _replyPreview(_jsonObject(json['preview']), messageType)
        : null,
    attachmentCount: _int(json['attachment_count']) ?? 0,
  );
}

ReplyPreview? _replyPreview(
  Map<String, dynamic> json,
  MessageType fallbackType,
) {
  if (json.isEmpty) return null;
  try {
    return ReplyPreview(
      kind: _messageType(_string(json['kind']) ?? fallbackType.name),
      resourceId: _string(json['resource_id']),
      thumbnailResourceId: _string(json['thumbnail_resource_id']),
      previewUrl: _string(json['preview_url']),
      width: _int(json['width']),
      height: _int(json['height']),
      durationMs: _int(json['duration_ms']),
      fileName: _string(json['file_name']),
      fileSize: _int(json['file_size']),
      mimeType: _string(json['mime_type']),
      name: _string(json['name']),
      address: _string(json['address']),
      sharedUserId: _string(json['shared_user_id']),
      displayName: _string(json['display_name']),
      avatarUrl: _string(json['avatar_url']),
    );
  } catch (_) {
    // 单个预览字段脏数据不能导致整条消息解析失败；摘要仍可独立渲染。
    return null;
  }
}

String _replyFallback(MessageType type) => switch (type) {
  MessageType.image => '[图片]',
  MessageType.file => '[文件]',
  _ => '[消息]',
};

MessageType _messageType(String value) {
  return switch (value) {
    'image' => MessageType.image,
    'file' => MessageType.file,
    'system' => MessageType.system,
    'recall' || 'recalled' => MessageType.recall,
    _ => MessageType.text,
  };
}

ConversationType _conversationType(String? value) {
  return switch (value) {
    '2' || 'group' || 'group_chat' => throw const FormatException('社区版不支持群会话'),
    _ => ConversationType.single,
  };
}

DateTime _time(Object? value) {
  if (value is int) {
    final ms = value > 1000000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
  }
  return DateTime.now().toUtc();
}

String? _string(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('data 必须为 JSON 对象');
}

List<Object?> _jsonList(Object? value) {
  if (value is List) return value;
  return const [];
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item.toString()));
}

String _formatSize(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
}

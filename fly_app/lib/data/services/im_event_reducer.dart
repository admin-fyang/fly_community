/// IM 统一事件归约器。
///
/// `/sync` 与 Centrifugo 都必须调用本类，避免实时与补偿链路产生不同的数据语义。
library;

import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/log_util.dart';
import '../enums/conversation_type.dart';
import '../enums/message_status.dart';
import '../enums/message_type.dart';
import '../local/im_local_database.dart';
import '../local/im_local_mapper.dart';
import '../models/im_api_models.dart';
import '../models/directory_models.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class UnsupportedImEventException implements Exception {
  const UnsupportedImEventException(this.eventType);
  final String eventType;
}

class ImEventApplyResult {
  const ImEventApplyResult({
    required this.event,
    required this.changed,
    required this.directoryChanged,
    this.changedConversationId,
  });

  final Map<String, dynamic> event;
  final bool changed;
  final bool directoryChanged;
  final String? changedConversationId;
}

class ImEventReducer {
  ImEventReducer(this._database);

  final ImLocalDatabase _database;

  /// 只列出当前客户端已经完整归约的事件。
  ///
  /// 只有具备完整 SQLite 归约语义的基础事件才能进入此集合。
  static const _implementedTypes = {
    'message_created',
    'message_recalled',
    'message_deleted_for_me',
    'conversation_updated',
    'receipt_updated',
    'notification_created',
    'notification_updated',
    'user_profile_updated',
  };

  Future<ImEventApplyResult> apply({
    required String userId,
    required Map<String, dynamic> event,
  }) async {
    final eventId = event['event_id']?.toString() ?? '';
    final eventType = event['event_type']?.toString() ?? '';
    try {
      final result = await _database.transaction(
        (tx) => applyInTransaction(tx, userId: userId, event: event),
      );
      await publish(result);
      return result;
    } on UnsupportedImEventException {
      if (eventId.isNotEmpty) {
        await _database.retainUnsupportedEvent(
          userId: userId,
          eventId: eventId,
          eventType: eventType.isEmpty ? 'invalid' : eventType,
          rawEvent: event,
        );
      }
      rethrow;
    } on FormatException {
      if (eventId.isNotEmpty) {
        await _database.retainUnsupportedEvent(
          userId: userId,
          eventId: eventId,
          eventType: eventType,
          rawEvent: event,
        );
      }
      rethrow;
    }
  }

  /// 在调用方事务内归约单个事件；HTTP Sync 用它把整页事件与游标原子提交。
  Future<ImEventApplyResult> applyInTransaction(
    Transaction tx, {
    required String userId,
    required Map<String, dynamic> event,
  }) async {
    final eventId = event['event_id']?.toString().trim() ?? '';
    final eventType = event['event_type']?.toString() ?? '';
    final revision = BigInt.tryParse(eventId);
    if (eventId.isEmpty ||
        revision == null ||
        revision.isNegative ||
        !_implementedTypes.contains(eventType)) {
      throw UnsupportedImEventException(eventType);
    }
    if (await _database.isEventApplied(tx, userId: userId, eventId: eventId)) {
      return ImEventApplyResult(
        event: event,
        changed: false,
        directoryChanged: false,
      );
    }
    var directoryChanged = false;
    final payload = _object(event['payload']);
    final rawDirectoryChanges = payload['directory_changes'];
    if (rawDirectoryChanges is List && rawDirectoryChanges.isNotEmpty) {
      final changes = rawDirectoryChanges.map((item) {
        if (item is! Map) {
          throw const FormatException('目录变更项格式不正确');
        }
        final json = item.map((key, value) => MapEntry(key.toString(), value));
        final itemRevision = json['revision']?.toString().trim();
        if (itemRevision != null &&
            itemRevision.isNotEmpty &&
            itemRevision != eventId) {
          throw const FormatException('目录变更revision与事件event_id不一致');
        }
        return DirectoryChange.fromJson(json);
      });
      directoryChanged = await _database.applyDirectoryChangesInTransaction(
        tx,
        changes: changes,
        revision: eventId,
      );
    }

    switch (eventType) {
      case 'user_profile_updated':
        // 资料快照由 UserProfileSyncService 合并到全局会话；此处纳入
        // 归约事务以保证事件游标推进、重复事件幂等和未知事件保护一致。
        _profilePayload(payload);
      case 'message_created':
        await _upsertMessage(tx, payload, event, currentUserId: userId);
        await _upsertConversation(tx, payload, event, currentUserId: userId);
      case 'message_recalled':
        final recalledMessageId = _requiredEventId(event, 'message_id');
        await tx.update(
          'local_message',
          {
            'status': 'recalled',
            'payload_json': await _recalledPayload(tx, recalledMessageId),
          },
          where: 'message_id = ?',
          whereArgs: [recalledMessageId],
        );
        await _hideLocalReplySnapshots(tx, recalledMessageId);
        await _applyConversationAfterMessageMutation(tx, payload, event);
      case 'message_deleted_for_me':
        final deletedMessageId = _requiredEventId(event, 'message_id');
        await tx.update(
          'local_message',
          {'visibility_state': 'deleted'},
          where: 'message_id = ?',
          whereArgs: [deletedMessageId],
        );
        await _applyConversationAfterMessageMutation(tx, payload, event);
      case 'conversation_updated':
        final conversation = _conversationData(payload, event);
        final conversationId = _conversationId(conversation, event);
        final isDeleted =
            _bool(
              conversation['conversation_deleted'] ??
                  conversation['member_deleted'] ??
                  conversation['deleted'],
            ) ==
            true;
        if (isDeleted && conversationId.isNotEmpty) {
          await _database.deleteConversationInTransaction(
            tx,
            conversationId: conversationId,
            clearedBeforeSeq: _int(conversation['cleared_before_seq']),
          );
        } else if (conversationId.isNotEmpty) {
          await _upsertConversation(tx, payload, event, currentUserId: userId);
          await _applyClearWatermark(tx, payload, event);
        } else if (_object(payload['contact']).isEmpty &&
            (rawDirectoryChanges is! List || rawDirectoryChanges.isEmpty)) {
          throw const FormatException(
            'conversation_updated 缺少 conversation_id',
          );
        }
      case 'receipt_updated':
        await _upsertReceipt(tx, event, currentUserId: userId);
      case 'notification_created':
      case 'notification_updated':
        await _upsertNotification(tx, payload, event);
    }
    await _database.markEventApplied(
      tx,
      userId: userId,
      eventId: eventId,
      eventType: eventType,
      rawEvent: event,
    );
    final conversationId = _conversationId(
      _conversationData(payload, event),
      event,
    );
    return ImEventApplyResult(
      event: event,
      changed: true,
      directoryChanged: directoryChanged,
      changedConversationId:
          _changesConversationProjection(eventType) && conversationId.isNotEmpty
          ? conversationId
          : null,
    );
  }

  void _profilePayload(Map<String, dynamic> payload) {
    final raw = payload['user'];
    if (raw is! Map)
      throw const FormatException('user_profile_updated 缺少 user');
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    if (json['id'] is! String || json['profile_version'] is! int) {
      throw const FormatException('user_profile_updated 资料格式不正确');
    }
  }

  /// 仅在承载该结果的 SQLite 事务提交后发布响应式变更。
  Future<void> publish(
    ImEventApplyResult result, {
    bool publishCall = true,
  }) async {
    if (!result.changed) return;
    if (result.directoryChanged) await _database.publishDirectoryChange();
    final conversationId = result.changedConversationId;
    if (conversationId != null) {
      await _database.publishConversationChange(conversationId);
    }
  }

  Future<void> _upsertMessage(
    dynamic tx,
    Map<String, dynamic> payload,
    Map<String, dynamic> event, {
    required String currentUserId,
  }) async {
    final message = _object(payload['message']);
    final messageId =
        message['message_id']?.toString() ??
        event['message_id']?.toString() ??
        '';
    if (messageId.isEmpty) {
      throw const FormatException('message_created 缺少 message_id');
    }
    final conversationId =
        message['conversation_id']?.toString() ??
        event['conversation_id']?.toString() ??
        '';
    if (conversationId.isEmpty) {
      throw const FormatException('message_created 缺少 conversation_id');
    }
    final snapshot = ImMessageDto.fromJson({
      ...message,
      'message_id': messageId,
      'conversation_id': conversationId,
    }).toUiModel(currentUserId: currentUserId);
    final clientMessageId = message['client_msg_id']?.toString() ?? '';
    if (clientMessageId.isNotEmpty && snapshot.isMine) {
      await _database.confirmPendingMessageInTransaction(
        tx,
        clientMessageId: clientMessageId,
        serverMessage: snapshot,
      );
    } else {
      await _database.upsertMessageInTransaction(tx, snapshot);
    }
  }

  /// 将当前账号实际收到且与其相关的群管理事件投影为本地系统消息。
  ///
  /// 服务端只持久化定向可靠事件，不把提示写进群公共消息历史；因此这里必须
  /// 与 event_id 去重处于同一事务。无关接收者不会生成“你……”类提示。
  Future<void> _upsertConversation(
    dynamic tx,
    Map<String, dynamic> payload,
    Map<String, dynamic> event, {
    String? currentUserId,
  }) async {
    final conversation = _conversationData(payload, event);
    final id = _conversationId(conversation, event);
    if (id.isEmpty) {
      throw FormatException('${event['event_type']} 缺少 conversation_id');
    }
    if (_hasCompleteConversationProjection(conversation)) {
      final projection = ImConversationDto.fromJson({
        ...conversation,
        'conversation_id': id,
        '_current_user_id': currentUserId,
      }).toUiModel();
      await _database.upsertConversationProjectionInTransaction(tx, projection);
      return;
    }
    final existing = await tx.query(
      'local_conversation',
      columns: const [
        'type',
        'title',
        'last_message_id',
        'last_seq',
        'unread_count',
        'is_pinned',
        'is_muted',
        'updated_at',
        'payload_json',
      ],
      where: 'conversation_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final previous = existing.isEmpty
        ? const <String, Object?>{}
        : existing.first;
    final previousSnapshot = decodeLocalConversation(previous['payload_json']);
    final rawMessage = _object(payload['message']);
    // 旧版事件仅允许更新本地已经存在的会话。未知会话没有标题、头像或
    // 权威最后消息时不能生成“会话”占位行，否则事件虽然推进成功，首页
    // 却会长期保存无法修复的错误投影。
    if (existing.isEmpty) {
      _logIncompleteConversationProjection(payload, event, conversation);
      throw const FormatException('实时事件缺少未知会话的完整 conversation 投影');
    }
    final eventMessage = rawMessage.isEmpty
        ? null
        : ImMessageDto.fromJson({
            ...rawMessage,
            'message_id': rawMessage['message_id'] ?? event['message_id'],
            'conversation_id': id,
          }).toUiModel(currentUserId: currentUserId);
    final eventTime = _int(event['server_time']);
    final lastSeq = _int(conversation['last_seq']) ?? eventMessage?.seq;
    var nextSnapshot = previousSnapshot?.copyWith(
      title: conversation['title']?.toString(),
      unreadCount: _int(conversation['unread_count']),
      isPinned: conversation.containsKey('is_pinned')
          ? _bool(conversation['is_pinned']) == true
          : null,
      isMuted: conversation.containsKey('is_muted')
          ? _bool(conversation['is_muted']) == true
          : null,
    );
    if (nextSnapshot != null && eventMessage != null) {
      nextSnapshot = nextSnapshot.replaceLastMessage(
        type: eventMessage.type,
        text: eventMessage.text,
        senderName: eventMessage.senderName,
        reply: eventMessage.reply,
        messageIsMine: eventMessage.isMine,
        messageId:
            conversation['last_message_id']?.toString() ??
            event['message_id']?.toString() ??
            eventMessage.id,
        lastSeq: lastSeq ?? nextSnapshot.lastSeq,
        time: eventTime == null
            ? eventMessage.time
            : DateTime.fromMillisecondsSinceEpoch(
                eventTime * 1000,
                isUtc: true,
              ),
        unreadCount: _int(conversation['unread_count']),
      );
    }
    await tx.insert('local_conversation', {
      'conversation_id': id,
      'type':
          conversation['conversation_type']?.toString() ??
          previous['type']?.toString() ??
          'single',
      'title':
          conversation['title']?.toString() ??
          previous['title']?.toString() ??
          '会话',
      'last_message_id':
          conversation['last_message_id']?.toString() ??
          event['message_id']?.toString() ??
          previous['last_message_id'],
      'last_seq':
          lastSeq?.toString() ?? previous['last_seq']?.toString() ?? '0',
      'unread_count':
          _int(conversation['unread_count']) ?? previous['unread_count'] ?? 0,
      'is_pinned': conversation.containsKey('is_pinned')
          ? (_bool(conversation['is_pinned']) == true ? 1 : 0)
          : previous['is_pinned'] ?? 0,
      'is_muted': conversation.containsKey('is_muted')
          ? (_bool(conversation['is_muted']) == true ? 1 : 0)
          : previous['is_muted'] ?? 0,
      'updated_at': eventTime ?? previous['updated_at'] ?? 0,
      'payload_json': nextSnapshot == null
          ? previous['payload_json']
          : encodeLocalConversation(nextSnapshot),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _applyConversationAfterMessageMutation(
    dynamic tx,
    Map<String, dynamic> payload,
    Map<String, dynamic> event,
  ) async {
    final conversation = _conversationData(payload, event);
    final conversationId = _conversationId(conversation, event);
    if (conversationId.isEmpty) {
      throw FormatException('${event['event_type']} 缺少 conversation_id');
    }
    if (_hasCompleteConversationProjection(conversation)) {
      await _upsertConversation(tx, payload, event);
      return;
    }
    final existing = await tx.query(
      'local_conversation',
      columns: const ['conversation_id'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (existing.isEmpty) {
      _logIncompleteConversationProjection(payload, event, conversation);
      throw const FormatException('消息变更事件缺少未知会话的完整 conversation 投影');
    }
    // 兼容已经落到设备上的旧版事件；新协议始终使用后端权威 last_message。
    await _database.rebuildConversationPreviewInTransaction(tx, conversationId);
  }

  Future<void> _upsertNotification(
    dynamic tx,
    Map<String, dynamic> payload,
    Map<String, dynamic> event,
  ) async {
    final notification = _object(payload['notification']);
    final id =
        event['notification_id']?.toString() ??
        notification['notification_id']?.toString() ??
        '';
    if (id.isEmpty) {
      throw FormatException('${event['event_type']} 缺少 notification_id');
    }
    await tx.insert('local_notification', {
      'notification_id': id,
      'notification_type':
          notification['notification_type']?.toString() ?? 'system',
      'title': notification['title']?.toString() ?? '',
      'content': notification['content']?.toString(),
      'action_status': notification['action_status']?.toString(),
      'is_read': notification['is_read'] == true ? 1 : 0,
      'create_time':
          _int(notification['create_time']) ?? _int(event['server_time']) ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertReceipt(
    dynamic tx,
    Map<String, dynamic> event, {
    required String currentUserId,
  }) async {
    final receipt = ImReceiptUpdate.fromEvent(event);
    await _database.upsertConversationReadCursor(
      tx,
      conversationId: receipt.conversationId,
      userId: receipt.userId,
      lastReadSeq: receipt.lastReadSeq,
      unreadCount: receipt.unreadCount,
      updatedAt: _int(event['server_time']) ?? 0,
    );
    if (receipt.userId == currentUserId) {
      await _database.updateConversationUnreadInTransaction(
        tx,
        conversationId: receipt.conversationId,
        unreadCount: receipt.unreadCount,
      );
    }
  }

  Future<String?> _recalledPayload(dynamic tx, String messageId) async {
    final rows = await tx.query(
      'local_message',
      columns: const ['payload_json'],
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final message = decodeLocalMessage(rows.first['payload_json']);
    if (message == null) return null;
    return encodeLocalMessage(
      message.copyWith(
        type: MessageType.recall,
        text: message.isMine ? '你撤回了一条消息' : '对方撤回了一条消息',
      ),
    );
  }

  /// 撤回原消息时，在同一事件事务内同步隐藏所有直接引用快照。
  Future<void> _hideLocalReplySnapshots(dynamic tx, String messageId) async {
    final rows = await tx.query(
      'local_message',
      columns: const ['local_id', 'payload_json'],
      where: 'reply_message_id = ?',
      whereArgs: [messageId],
    );
    for (final row in rows) {
      final message = decodeLocalMessage(row['payload_json']);
      final reply = message?.reply;
      if (message == null || reply == null) continue;
      await tx.update(
        'local_message',
        {
          'payload_json': encodeLocalMessage(
            message.copyWith(reply: reply.recalled()),
          ),
        },
        where: 'local_id = ?',
        whereArgs: [row['local_id']],
      );
    }
  }

  /// 清空记录只改变当前用户本地可见性，不篡改其他消息保存的引用快照。
  Future<void> _applyClearWatermark(
    dynamic tx,
    Map<String, dynamic> payload,
    Map<String, dynamic> event,
  ) async {
    final conversation = _conversationData(payload, event);
    final clearedBeforeSeq = _int(
      conversation['cleared_before_seq'] ?? payload['cleared_before_seq'],
    );
    final conversationId = _conversationId(conversation, event);
    if (clearedBeforeSeq == null || conversationId.isEmpty) return;
    await _database.clearConversationInTransaction(
      tx,
      conversationId: conversationId,
      clearedBeforeSeq: clearedBeforeSeq,
    );
  }
}

bool _changesConversationProjection(String eventType) => switch (eventType) {
  'message_created' ||
  'message_recalled' ||
  'message_deleted_for_me' ||
  'conversation_updated' ||
  'receipt_updated' => true,
  _ => false,
};

/// 兼容后端三种已上线载荷：嵌套 conversation、payload 直接字段、事件直接字段。
Map<String, dynamic> _conversationData(
  Map<String, dynamic> payload,
  Map<String, dynamic> event,
) {
  final nested = _object(payload['conversation']);
  const keys = {
    'conversation_id',
    'conversation_type',
    'title',
    'last_message_id',
    'last_seq',
    'unread_count',
    'is_pinned',
    'is_muted',
    'cleared_before_seq',
    'conversation_deleted',
    'member_deleted',
    'deleted',
  };
  final result = <String, dynamic>{...nested};
  for (final source in [payload, event]) {
    for (final key in keys) {
      if (source.containsKey(key)) result[key] = source[key];
    }
  }
  return result;
}

/// 判断事件是否携带了可独立构造首页列表项的权威投影。
///
/// 可空字段也必须显式出现，例如无头像时 `avatar_url=null`、无消息时
/// `last_message=null`。这样客户端能区分“后端明确清空”和“旧协议漏字段”。
bool _hasCompleteConversationProjection(Map<String, dynamic> conversation) {
  const requiredKeys = {
    'conversation_type',
    'target_id',
    'title',
    'avatar_url',
    'last_message_id',
    'last_seq',
    'unread_count',
    'is_pinned',
    'is_muted',
    'update_time',
    'last_message',
  };
  return requiredKeys.every(conversation.containsKey);
}

/// 输出结构级协议诊断，不打印任何字段值。
///
/// `payload_keys` 与 `nested_keys` 可判断后端使用嵌套还是平铺结构；
/// `missing_fields` 直接指出客户端无法创建首页会话投影的原因。消息正文、
/// Token、头像和附件 URL 都不会进入日志。
void _logIncompleteConversationProjection(
  Map<String, dynamic> payload,
  Map<String, dynamic> event,
  Map<String, dynamic> conversation,
) {
  final nested = _object(payload['conversation']);
  final payloadKeys = payload.keys.toList()..sort();
  final nestedKeys = nested.keys.toList()..sort();
  final missingFields = _missingConversationProjectionFields(conversation);
  final source = nested.isNotEmpty
      ? 'nested'
      : conversation.isNotEmpty
      ? 'flat_or_envelope'
      : 'missing';
  LogUtil.d(
    'event_id=${event['event_id'] ?? '-'} '
    'type=${event['event_type'] ?? '-'} '
    'conversation_id=${event['conversation_id'] ?? '-'} source=$source '
    'payload_keys=$payloadKeys nested_keys=$nestedKeys '
    'missing_fields=$missingFields',
    tag: 'IM reducer',
  );
}

List<String> _missingConversationProjectionFields(
  Map<String, dynamic> conversation,
) {
  const requiredKeys = {
    'conversation_type',
    'target_id',
    'title',
    'avatar_url',
    'last_message_id',
    'last_seq',
    'unread_count',
    'is_pinned',
    'is_muted',
    'update_time',
    'last_message',
  };
  final missing = requiredKeys
      .where((key) => !conversation.containsKey(key))
      .toList();
  missing.sort();
  return missing;
}

String _conversationId(
  Map<String, dynamic> conversation,
  Map<String, dynamic> event,
) =>
    event['conversation_id']?.toString() ??
    conversation['conversation_id']?.toString() ??
    '';

String _requiredEventId(Map<String, dynamic> event, String key) {
  final value = event[key]?.toString() ?? '';
  if (value.isEmpty) {
    throw FormatException('${event['event_type']} 缺少 $key');
  }
  return value;
}

Map<String, dynamic> _object(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

int? _int(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

bool? _bool(Object? value) => switch (value) {
  true || 1 || '1' || 'true' => true,
  false || 0 || '0' || 'false' => false,
  _ => null,
};

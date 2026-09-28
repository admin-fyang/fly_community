library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/repositories/im_repository.dart';
import '../local/session_storage.dart';
import '../local/im_local_database.dart';
import '../models/conversation_model.dart';
import '../models/conversation_projection_change.dart';
import '../models/im_api_models.dart';
import '../models/message_model.dart';

class ImRepositoryImpl implements ImRepository {
  const ImRepositoryImpl(this._client, this._storage, this._database);

  final ApiClient _client;
  final SessionStorage _storage;
  final ImLocalDatabase _database;

  @override
  Stream<ConversationProjectionChange> watchConversationChanges() =>
      _database.conversationChanges;

  @override
  Future<void> reportProtocolIssue({
    required String event,
    required String clientVersion,
    required String platform,
    required String protocolVersion,
    required Map<String, String> context,
  }) async {
    final accepted = await _client.post<bool>(
      ApiPaths.imProtocolIssues,
      data: {
        'event': event,
        'client_version': clientVersion,
        'platform': platform,
        'protocol_version': protocolVersion,
        'context': context,
      },
      decoder: (data) {
        final json = _jsonObject(data);
        return json['accepted'] == true;
      },
    );
    if (!accepted) throw const FormatException('协议问题上报未被服务端接受');
  }

  @override
  Future<ImConversationPage> getConversations({
    int limit = 20,
    int? beforeUpdateTime,
    String? beforeConversationId,
  }) async {
    final currentUserId = await _currentUserId();
    final projectionRevisions = _database
        .captureConversationProjectionRevisions();
    final remotePage = await _client.get<ImConversationPage>(
      _withQuery(ApiPaths.imConversations, {
        'limit': '$limit',
        if (beforeUpdateTime != null) 'before_update_time': '$beforeUpdateTime',
        if (beforeConversationId != null && beforeConversationId.isNotEmpty)
          'before_conversation_id': beforeConversationId,
      }),
      decoder: (data) {
        final page = ImConversationPage.fromJson(
          _jsonObject(data),
          pageSize: limit,
          currentUserId: currentUserId,
        );
        page.items.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.time.compareTo(a.time);
        });
        return page;
      },
    );
    for (final entry in remotePage.readStates.entries) {
      await _database.cacheConversationReadState(
        conversationId: entry.key,
        readState: entry.value,
      );
    }
    await _database.cacheConversations(
      remotePage.items,
      expectedRevisions: projectionRevisions,
    );
    final cached = await _database.readCachedConversations();
    final cachedById = {for (final item in cached) item.id: item};
    return ImConversationPage(
      items: remotePage.items
          .map((item) => cachedById[item.id] ?? item)
          .toList(),
      nextBeforeUpdateTime: remotePage.nextBeforeUpdateTime,
      nextBeforeConversationId: remotePage.nextBeforeConversationId,
      hasMore: remotePage.hasMore,
      readStates: remotePage.readStates,
    );
  }

  @override
  Future<List<ConversationModel>> getCachedConversations({int limit = 200}) {
    return _database.readCachedConversations(limit: limit);
  }

  @override
  Future<ConversationModel> resolveSingleConversation(
    String targetUserId,
  ) async {
    final currentUserId = await _currentUserId();
    return _client.post<ConversationModel>(
      ApiPaths.imSingleConversation,
      data: {'target_user_id': targetUserId},
      decoder: (data) => ImConversationDto.fromJson({
        ..._jsonObject(data),
        '_current_user_id': currentUserId,
      }).toUiModel(),
    );
  }

  @override
  Future<CentrifugoConnectionToken> getCentrifugoToken() {
    return _client.post<CentrifugoConnectionToken>(
      ApiPaths.imCentrifugoToken,
      decoder: (data) => CentrifugoConnectionToken.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<ImHistoryPage> getMessages({
    required String conversationId,
    int limit = 30,
    String? beforeSeq,
  }) async {
    final currentUserId = await _currentUserId();
    final remotePage = await _client.get<ImHistoryPage>(
      _withQuery(ApiPaths.imConversationMessages(conversationId), {
        'limit': '$limit',
        if (beforeSeq != null && beforeSeq.isNotEmpty) 'before_seq': beforeSeq,
      }),
      decoder: (data) => ImHistoryPage.fromJson(
        _jsonObject(data),
        currentUserId: currentUserId,
        pageSize: limit,
      ),
    );
    final readState = remotePage.readState;
    if (readState != null) {
      await _database.cacheConversationReadState(
        conversationId: conversationId,
        readState: readState,
      );
    }
    await _database.cacheMessages(remotePage.items);
    final cachedItems = await _database.readCachedMessages(
      conversationId: conversationId,
      currentUserId: currentUserId ?? '',
      limit: limit,
      beforeSeq: beforeSeq,
    );
    return ImHistoryPage(
      items: cachedItems,
      nextBeforeSeq: remotePage.nextBeforeSeq,
      hasMore: remotePage.hasMore,
      readState: remotePage.readState,
    );
  }

  @override
  Future<List<MessageModel>> getCachedMessages({
    required String conversationId,
    int limit = 30,
    String? beforeSeq,
  }) async {
    final currentUserId = await _currentUserId();
    return _database.readCachedMessages(
      conversationId: conversationId,
      currentUserId: currentUserId ?? '',
      limit: limit,
      beforeSeq: beforeSeq,
    );
  }

  @override
  Future<MessageModel> sendText({
    required String conversationId,
    required String clientMsgId,
    required String bodyText,
    String? replyMessageId,
  }) {
    return _send({
      'conversation_id': conversationId,
      'client_msg_id': clientMsgId,
      'body_text': bodyText,
      if (replyMessageId != null && replyMessageId.isNotEmpty)
        'reply_message_id': replyMessageId,
    });
  }

  @override
  Future<MessageModel> sendRichMessage({
    required String conversationId,
    required String clientMsgId,
    required String messageType,
    List<MessageAttachmentDto> attachments = const [],
    String? replyMessageId,
  }) {
    return _send({
      'conversation_id': conversationId,
      'client_msg_id': clientMsgId,
      'message_type': messageType,
      if (attachments.isNotEmpty)
        'attachments': attachments.map((item) => item.toJson()).toList(),
      if (replyMessageId != null && replyMessageId.isNotEmpty)
        'reply_message_id': replyMessageId,
    });
  }

  @override
  Future<ImSyncResult> sync({
    required String cursor,
    required String deviceId,
    int limit = 200,
  }) async {
    final currentUserId = await _currentUserId();
    return _client.get<ImSyncResult>(
      _withQuery(ApiPaths.imSync, {
        'after_event_id': cursor,
        'limit': '$limit',
        'device_id': deviceId,
      }),
      decoder: (data) => ImSyncResult.fromJson(
        _jsonObject(data),
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  Future<void> markRead({required String conversationId, required int seq}) {
    return _client.post<void>(
      ApiPaths.imConversationRead(conversationId),
      data: {'seq': seq},
      decoder: (_) {},
    );
  }

  @override
  Future<MessageModel> recallMessage({
    required String messageId,
    String reason = '用户主动撤回',
  }) async {
    final currentUserId = await _currentUserId();
    return _client.post<MessageModel>(
      ApiPaths.imMessageRecall(messageId),
      data: {'reason': reason},
      decoder: (data) => ImSendResult.fromJson(
        _jsonObject(data),
        currentUserId: currentUserId,
      ).message,
    );
  }

  @override
  Future<void> deleteMessageForMe(String messageId) {
    return _client.delete<void>(ApiPaths.imMessage(messageId), decoder: (_) {});
  }

  @override
  Future<void> clearConversationMessages(ConversationLocator locator) async {
    final result = await _client.delete<Map<String, dynamic>>(
      ApiPaths.imConversationMessagesMutation,
      data: locator.toJson(),
      decoder: _jsonObject,
    );
    final responseConversationId = result['conversation_id']?.toString() ?? '';
    final conversationId = responseConversationId.isNotEmpty
        ? responseConversationId
        : locator.conversationId?.trim() ?? '';
    final clearedBeforeSeq = int.tryParse(
      result['cleared_before_seq']?.toString() ?? '',
    );
    if (conversationId.isNotEmpty && clearedBeforeSeq != null) {
      await _database.clearConversationLocally(
        conversationId: conversationId,
        clearedBeforeSeq: clearedBeforeSeq,
      );
    }
  }

  @override
  Future<void> deleteConversation(ConversationLocator locator) async {
    final result = await _client.delete<Map<String, dynamic>>(
      ApiPaths.imConversations,
      data: locator.toJson(),
      decoder: _jsonObject,
    );
    final responseConversationId = result['conversation_id']?.toString() ?? '';
    final conversationId = responseConversationId.isNotEmpty
        ? responseConversationId
        : locator.conversationId?.trim() ?? '';
    final clearedBeforeSeq = int.tryParse(
      result['cleared_before_seq']?.toString() ?? '',
    );
    if (conversationId.isNotEmpty) {
      await _database.deleteConversationLocally(
        conversationId: conversationId,
        clearedBeforeSeq: clearedBeforeSeq,
      );
    }
  }

  @override
  Future<void> updateConversationMuted({
    required String conversationId,
    required bool isMuted,
  }) async {
    await _client.patch<void>(
      ApiPaths.imConversationSettings(conversationId),
      data: {'is_muted': isMuted},
      decoder: (_) {},
    );
    await _database.updateConversationMutedLocally(
      conversationId: conversationId,
      isMuted: isMuted,
    );
  }

  @override
  Future<ConversationBatchResult> clearConversations(
    List<String> conversationIds,
  ) async {
    final ids = _normalizedBatchIds(conversationIds);
    final result = await _client.delete<ConversationBatchResult>(
      ApiPaths.imConversationMessagesBatch,
      data: {'conversation_ids': ids},
      decoder: _conversationBatchResult,
    );
    await _database.clearConversationsLocally(result.successfulIds.toList());
    return result;
  }

  @override
  Future<ConversationBatchResult> deleteConversations(
    List<String> conversationIds,
  ) async {
    final ids = _normalizedBatchIds(conversationIds);
    final result = await _client.delete<ConversationBatchResult>(
      ApiPaths.imConversationsBatch,
      data: {'conversation_ids': ids},
      decoder: _conversationBatchResult,
    );
    await _database.deleteConversationsLocally(result.successfulIds.toList());
    return result;
  }

  @override
  Future<ConversationBatchResult> updateConversationsMuted({
    required List<String> conversationIds,
    required bool isMuted,
  }) async {
    final ids = _normalizedBatchIds(conversationIds);
    final result = await _client.patch<ConversationBatchResult>(
      ApiPaths.imConversationsMuteBatch,
      data: {'conversation_ids': ids, 'is_muted': isMuted},
      decoder: _conversationBatchResult,
    );
    await _database.updateConversationSettingsLocally(
      conversationIds: result.successfulIds.toList(),
      isMuted: isMuted,
    );
    return result;
  }

  @override
  Future<ConversationBatchResult> updateConversationsPinned({
    required List<String> conversationIds,
    required bool isPinned,
  }) async {
    final ids = _normalizedBatchIds(conversationIds);
    final result = await _client.patch<ConversationBatchResult>(
      ApiPaths.imConversationsPinBatch,
      data: {'conversation_ids': ids, 'is_pinned': isPinned},
      decoder: _conversationBatchResult,
    );
    await _database.updateConversationSettingsLocally(
      conversationIds: result.successfulIds.toList(),
      isPinned: isPinned,
    );
    return result;
  }

  Future<MessageModel> _send(Map<String, dynamic> body) async {
    final currentUserId = await _currentUserId();
    return _client.post<MessageModel>(
      ApiPaths.imMessages,
      data: body,
      decoder: (data) => ImSendResult.fromJson(
        _jsonObject(data),
        currentUserId: currentUserId,
      ).message,
    );
  }

  Future<String?> _currentUserId() async => (await _storage.readUser())?.id;
}

String _withQuery(String path, Map<String, String> query) {
  final uri = Uri(path: path, queryParameters: query);
  return uri.toString();
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('data 必须为 JSON 对象');
}

/// 批量接口统一限制为 1-100 个会话；客户端先去重，避免浪费服务端配额。
List<String> _normalizedBatchIds(List<String> conversationIds) {
  final ids = <String>{};
  for (final rawId in conversationIds) {
    final id = rawId.trim();
    if (id.isNotEmpty) ids.add(id);
  }
  if (ids.isEmpty) {
    throw ArgumentError.value(conversationIds, 'conversationIds');
  }
  if (ids.length > 100) {
    throw RangeError.range(ids.length, 1, 100, 'conversationIds.length');
  }
  return ids.toList(growable: false);
}

ConversationBatchResult _conversationBatchResult(Object? value) {
  final json = _jsonObject(value);

  List<String> readIds(String key) {
    final raw = json[key];
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  final failures = <ConversationBatchFailure>[];
  final rawFailures = json['failed_items'];
  if (rawFailures is List) {
    for (final item in rawFailures) {
      if (item is! Map) continue;
      final failure = item.map((key, value) => MapEntry(key.toString(), value));
      final id =
          (failure['conversation_id'] ?? failure['id'])?.toString().trim() ??
          '';
      failures.add(
        ConversationBatchFailure(
          conversationId: id,
          message: (failure['message'] ?? failure['error_message'])?.toString(),
        ),
      );
    }
  }

  return ConversationBatchResult(
    requestedCount:
        int.tryParse(json['requested_count']?.toString() ?? '') ?? 0,
    succeededIds: readIds('succeeded_ids'),
    idempotentIds: readIds('idempotent_ids'),
    failedItems: failures,
  );
}

library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/repositories/contact_repository.dart';
import '../models/contact_model.dart';
import '../models/paged_result.dart';
import '../models/profile_detail_model.dart';
import '../local/im_local_database.dart';
import '../services/directory_sync_service.dart';

class ContactRepositoryImpl implements ContactRepository {
  const ContactRepositoryImpl(
    this._client, [
    this._database,
    this._directorySync,
  ]);

  final ApiClient _client;
  final ImLocalDatabase? _database;
  final DirectorySyncService? _directorySync;

  @override
  Future<void> refresh() async {
    await _directorySync?.requestIncrementalSync();
  }

  @override
  Future<void> refreshFromServer() async {
    final directorySync = _directorySync;
    if (directorySync != null) {
      await directorySync.calibrateIfNeeded(force: true);
      return;
    }

    // 无本地目录服务只会出现在精简测试或降级环境；仍发起真实请求，
    // 但不伪造无法持久化的权威本地快照。
    await _client.get<PagedResult<ContactModel>>(
      _withQuery(ApiPaths.contacts, const {'limit': '100'}),
      decoder: (data) {
        final json = _jsonObject(data);
        return PagedResult<ContactModel>(
          items: _jsonList(json['items'])
              .map((item) => ContactModel.fromContactJson(_jsonObject(item)))
              .toList(),
          nextCursor: json['next_cursor'] is String
              ? json['next_cursor'] as String
              : null,
        );
      },
    );
  }

  @override
  Stream<List<ContactModel>> watchContacts() async* {
    final database = _database;
    if (database == null) {
      yield await getContacts();
      return;
    }
    yield await database.readCachedContacts();
    await for (final _ in database.directoryChanges) {
      yield await database.readCachedContacts();
    }
  }

  @override
  Future<PagedResult<ContactModel>> getContactsPage({
    int limit = 50,
    String? cursor,
  }) async {
    if (cursor == null && _database != null && _directorySync != null) {
      await _directorySync.calibrateIfNeeded();
      return PagedResult<ContactModel>(
        items: await _database.readCachedContacts(),
      );
    }
    return _client.get<PagedResult<ContactModel>>(
      _withQuery(ApiPaths.contacts, {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      }),
      decoder: (data) {
        final json = _jsonObject(data);
        return PagedResult<ContactModel>(
          items: _jsonList(json['items'])
              .map((item) => ContactModel.fromContactJson(_jsonObject(item)))
              .toList(),
          nextCursor: json['next_cursor'] is String
              ? json['next_cursor'] as String
              : null,
        );
      },
    );
  }

  @override
  Future<List<ContactModel>> getContacts({
    int limit = 50,
    String? cursor,
  }) async {
    final page = await getContactsPage(limit: limit, cursor: cursor);
    return page.items;
  }

  @override
  Future<List<ContactModel>> searchUsers({
    required String keyword,
    int limit = 20,
    String? countryCode,
  }) {
    return _client.get<List<ContactModel>>(
      _withQuery(ApiPaths.userSearch, {
        'keyword': keyword.trim(),
        'limit': '$limit',
        if (countryCode != null && countryCode.isNotEmpty)
          'country_code': countryCode,
      }),
      decoder: (data) {
        final json = _jsonObject(data);
        return _jsonList(json['items'])
            .map((item) => ContactModel.fromSearchJson(_jsonObject(item)))
            .toList();
      },
    );
  }

  @override
  Future<ProfileDetailModel> getUserProfile(String userId) {
    return _client.get<ProfileDetailModel>(
      ApiPaths.userProfile(userId),
      decoder: (data) => ProfileDetailModel.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<void> requestFriend({
    required String targetUserId,
    String remark = '',
  }) {
    return _client.post<void>(
      ApiPaths.friendRequests,
      data: {'target_user_id': targetUserId, 'remark': remark},
      decoder: (_) {},
    );
  }

  @override
  Future<void> updateRemark({
    required String userId,
    required String remark,
  }) async {
    final token = await _directorySync?.captureToken();
    final response = await _client.patch<Map<String, dynamic>>(
      ApiPaths.contactRemark(userId),
      data: {'remark': remark},
      decoder: _jsonObject,
    );
    if (token != null) {
      await _directorySync?.applyMutationResponse(response, token: token);
    }
  }

  @override
  Future<void> updateSettings({
    required String userId,
    bool? isPinned,
    bool? isMuted,
  }) async {
    final token = await _directorySync?.captureToken();
    final response = await _client.patch<Map<String, dynamic>>(
      ApiPaths.contactSettings(userId),
      data: {
        if (isPinned != null) 'is_pinned': isPinned,
        if (isMuted != null) 'is_muted': isMuted,
      },
      decoder: _jsonObject,
    );
    if (token != null) {
      await _directorySync?.applyMutationResponse(response, token: token);
    }
  }

  @override
  Future<void> deleteContact(String userId) async {
    final token = await _directorySync?.captureToken();
    final response = await _client.delete<Map<String, dynamic>>(
      ApiPaths.contact(userId),
      decoder: _jsonObject,
    );
    if (token != null) {
      await _directorySync?.applyMutationResponse(response, token: token);
    }
  }

  @override
  Future<void> blockUser(String userId) async {
    final token = await _directorySync?.captureToken();
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.contactBlock(userId),
      decoder: _jsonObject,
    );
    if (token != null) {
      await _directorySync?.applyMutationResponse(response, token: token);
    }
  }

  @override
  Future<void> unblockUser(String userId) async {
    final token = await _directorySync?.captureToken();
    final response = await _client.delete<Map<String, dynamic>>(
      ApiPaths.contactBlock(userId),
      decoder: _jsonObject,
    );
    if (token != null) {
      await _directorySync?.applyMutationResponse(response, token: token);
    }
  }
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

List<Object?> _jsonList(Object? value) {
  if (value is List) return value;
  throw const FormatException('items 必须为 JSON 数组');
}

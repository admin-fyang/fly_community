library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/notification_model.dart';
import '../models/paged_result.dart';
import '../services/directory_sync_service.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this._client, [this._directorySync]);

  final ApiClient _client;
  final DirectorySyncService? _directorySync;

  @override
  Future<PagedResult<NotificationModel>> getNotificationsPage({
    int limit = 20,
    String? beforeNotificationId,
  }) {
    return _client.get<PagedResult<NotificationModel>>(
      _withQuery(ApiPaths.notifications, {
        'limit': '$limit',
        if (beforeNotificationId != null && beforeNotificationId.isNotEmpty)
          'before_notification_id': beforeNotificationId,
      }),
      decoder: (data) {
        final json = _jsonObject(data);
        return PagedResult<NotificationModel>(
          items: _jsonList(json['items'])
              .map((item) => NotificationModel.fromJson(_jsonObject(item)))
              .toList(),
          nextCursor: json['next_before_notification_id'] is String
              ? json['next_before_notification_id'] as String
              : null,
        );
      },
    );
  }

  @override
  Future<List<NotificationModel>> getNotifications({
    int limit = 20,
    String? beforeNotificationId,
  }) async {
    final page = await getNotificationsPage(
      limit: limit,
      beforeNotificationId: beforeNotificationId,
    );
    return page.items;
  }

  @override
  Future<int> getUnreadCount() {
    return _client.get<int>(
      ApiPaths.notificationUnreadCount,
      decoder: (data) {
        final json = _jsonObject(data);
        return json['unread_count'] is int ? json['unread_count'] as int : 0;
      },
    );
  }

  @override
  Future<NotificationModel> markRead(String notificationId) {
    return _client.post<NotificationModel>(
      ApiPaths.notificationRead(notificationId),
      decoder: (data) => NotificationModel.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<void> markAllRead() {
    return _client.post<void>(ApiPaths.notificationReadAll, decoder: (_) {});
  }

  @override
  Future<NotificationModel> handle({
    required String notificationId,
    required String action,
    String? reason,
  }) async {
    final body = <String, dynamic>{'action': action};
    final normalizedReason = reason?.trim();
    if (normalizedReason != null && normalizedReason.isNotEmpty) {
      body['reason'] = normalizedReason;
    }
    final token = await _directorySync?.captureToken();
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.notificationHandle(notificationId),
      data: body,
      decoder: _jsonObject,
    );
    final rawNotification = response['notification'];
    final notification = NotificationModel.fromJson(
      rawNotification is Map ? _jsonObject(rawNotification) : response,
    );
    if (action == 'accept' && token != null) {
      await _directorySync?.applyMutationResponse(response, token: token);
    }
    return notification;
  }

  @override
  Future<NotificationModel> deleteForMe(String notificationId) {
    return _client.delete<NotificationModel>(
      ApiPaths.notification(notificationId),
      decoder: (data) => NotificationModel.fromJson(_jsonObject(data)),
    );
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

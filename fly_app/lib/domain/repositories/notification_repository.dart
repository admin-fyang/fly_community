library;

import '../../data/models/notification_model.dart';
import '../../data/models/paged_result.dart';

abstract interface class NotificationRepository {
  Future<PagedResult<NotificationModel>> getNotificationsPage({
    int limit = 20,
    String? beforeNotificationId,
  });

  Future<List<NotificationModel>> getNotifications({
    int limit = 20,
    String? beforeNotificationId,
  });

  Future<int> getUnreadCount();

  Future<NotificationModel> markRead(String notificationId);

  Future<void> markAllRead();

  Future<NotificationModel> handle({
    required String notificationId,
    required String action,
    String? reason,
  });

  Future<NotificationModel> deleteForMe(String notificationId);
}

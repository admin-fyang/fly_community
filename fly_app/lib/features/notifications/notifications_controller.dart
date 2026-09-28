/// 消息通知页控制器。
///
/// 提供通知列表数据、顶栏搜索切换与关键词过滤。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'dart:async';

import 'package:get/get.dart';

import '../../data/enums/top_bar_mode.dart';
import '../../data/models/notification_model.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../data/services/im_sync_service.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import 'notification_unread_controller.dart';

/// 消息通知页状态(纯静态 + 顶栏搜索切换 + 本地关键词过滤)
class NotificationsController extends GetxController with PageReadTracking {
  /// 顶栏模式:普通(标题+搜索图标)↔ 搜索(输入框)
  final topBarMode = TopBarMode.normal.obs;
  final keyword = ''.obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final errorMessage = ''.obs;
  final hasMore = false.obs;

  NotificationUnreadController get unread =>
      Get.find<NotificationUnreadController>();

  final _all = <NotificationModel>[].obs;
  String? _nextBeforeNotificationId;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  void onInit() {
    super.onInit();
    // _all.assignAll(MockNotifications.list());
    loadNotifications();
    if (Get.isRegistered<ImSyncService>()) {
      _eventSubscription = Get.find<ImSyncService>().appliedEvents.listen((
        event,
      ) {
        final type = event['event_type']?.toString() ?? '';
        if (type == 'notification_created' || type == 'notification_updated') {
          loadNotifications(showActivity: false);
        }
      });
    }
  }

  @override
  void onClose() {
    _eventSubscription?.cancel();
    super.onClose();
  }

  /// 按标题/副标题关键词过滤
  List<NotificationModel> get filtered {
    final kw = keyword.value.trim().toLowerCase();
    if (kw.isEmpty) return _all;
    return _all
        .where(
          (n) =>
              n.title.toLowerCase().contains(kw) ||
              n.subtitle.toLowerCase().contains(kw),
        )
        .toList();
  }

  Future<void> loadNotifications({bool showActivity = true}) async {
    final finishPageRead = pageReads.begin('loadNotifications', visible: showActivity);
    try {
      isLoading.value = true;
      errorMessage.value = '';
      try {
        final repository = Get.find<NotificationRepository>();
        final page = await repository.getNotificationsPage();
        _all.assignAll(page.items);
        _nextBeforeNotificationId = page.nextCursor;
        hasMore.value = page.hasMore;
        await unread.refreshCount();
      } catch (_) {
        errorMessage.value = '通知加载失败，请稍后重试';
        pageReads.reportError(errorMessage.value);
      } finally {
        isLoading.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  Future<void> loadMore() async {
    final finishPageRead = pageReads.begin('loadMore');
    try {
      if (isLoadingMore.value ||
          !hasMore.value ||
          _nextBeforeNotificationId == null) {
        return;
      }
      isLoadingMore.value = true;
      try {
        final page = await Get.find<NotificationRepository>()
            .getNotificationsPage(
              beforeNotificationId: _nextBeforeNotificationId,
            );
        _all.addAll(page.items);
        _nextBeforeNotificationId = page.nextCursor;
        hasMore.value = page.hasMore;
      } catch (_) {
        errorMessage.value = '更多通知加载失败';
        pageReads.reportError(errorMessage.value);
      } finally {
        isLoadingMore.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  Future<void> markRead(NotificationModel notification) async {
    if (notification.notificationId.isEmpty) return;
    try {
      final updated = await Get.find<NotificationRepository>().markRead(
        notification.notificationId,
      );
      final index = _all.indexWhere(
        (item) => item.notificationId == updated.notificationId,
      );
      if (index >= 0) _all[index] = updated;
      if (!notification.isRead) {
        unread.decrement();
        unawaited(unread.refreshCount());
      }
    } catch (_) {
      errorMessage.value = '通知状态更新失败';
      AppToast.error(errorMessage.value);
    }
  }

  Future<void> openNotification(NotificationModel notification) async {
    if (!notification.isRead) {
      await markRead(notification);
    }
    if (notification.notificationType == 'friend_request' ||
        notification.notificationType == 'friend_rejected') {
      final changed = await Get.toNamed(
        AppRoutes.friendRequestDetail,
        arguments: notification,
      );
      if (changed == true) {
        await loadNotifications();
      }
      return;
    }
    AppToast.info('该通知暂无详情');
  }

  void openSearch() => topBarMode.value = TopBarMode.search;

  void closeSearch() {
    keyword.value = '';
    topBarMode.value = TopBarMode.normal;
  }

  void updateKeyword(String value) => keyword.value = value;
}

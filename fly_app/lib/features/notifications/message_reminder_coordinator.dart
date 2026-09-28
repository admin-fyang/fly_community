/// 已落库新消息的统一提醒协调层。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/local/app_settings_storage.dart';
import '../../data/local/session_storage.dart';
import '../../data/services/android_local_notification_service.dart';
import '../../data/services/im_event_reducer.dart';
import '../../routes/app_routes.dart';
import '../chat/chat_navigation.dart';

class MessageReminderCoordinator {
  MessageReminderCoordinator(this._session, this._settings, this._android);

  final SessionStorage _session;
  final AppSettingsStorage _settings;
  final AndroidLocalNotificationService _android;
  final Set<String> _handledEventIds = <String>{};
  final List<String> _handledEventOrder = <String>[];

  Future<void> handlePersistedRealtimeEvent(
    Map<String, dynamic> event,
    ImEventApplyResult? applyResult,
  ) async {
    await handlePersistedEvent(event, changed: applyResult?.changed == true);
  }

  /// FCM 前台同步与实时消息最终都进入这里；[changed] 必须表示消息已经成功
  /// 写入 SQLite，协调层不接受未持久化的推送 payload。
  Future<void> handlePersistedEvent(
    Map<String, dynamic> event, {
    required bool changed,
  }) async {
    if (!changed || event['event_type']?.toString() != 'message_created') {
      return;
    }
    final eventId = event['event_id']?.toString().trim() ?? '';
    if (eventId.isNotEmpty && !_remember(eventId)) return;
    final user = await _session.readUser();
    if (user == null) return;
    final settings = await _settings.readNotificationSettings();
    final content = AndroidLocalNotificationService.buildContent(
      event: event,
      currentUserId: user.id,
      settings: settings,
    );
    if (content == null) return;

    // 只有应用真正处于前台可交互状态时，当前聊天页才可以抑制提醒。
    // Home、锁屏或切到其他应用后，路由仍可能停留在聊天页；此时必须
    // 继续走 Android 系统消息通知，不能被 _isCurrentChat() 误判吞掉。
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != AppLifecycleState.resumed) {
      await _android.showMessage(content);
      return;
    }

    if (_isCurrentChat(content.conversationId)) return;

    // 产品策略：前台不显示应用内消息横幅。只保留原有声音/震动反馈。
    final feedback = <Future<void>>[];
    if (settings.inAppSoundEnabled) {
      feedback.add(_android.playDefaultMessageSound());
    }
    if (settings.inAppVibrateEnabled) {
      feedback.add(_android.vibrateShort());
    }
    await Future.wait(feedback);
  }

  bool _isCurrentChat(String conversationId) {
    final currentPath =
        Uri.tryParse(Get.currentRoute)?.path ?? Get.currentRoute;
    return currentPath == AppRoutes.chat &&
        Get.isRegistered<ChatRouteSession>() &&
        Get.find<ChatRouteSession>().conversationId == conversationId;
  }

  bool _remember(String eventId) {
    if (!_handledEventIds.add(eventId)) return false;
    _handledEventOrder.add(eventId);
    if (_handledEventOrder.length > 200) {
      _handledEventIds.remove(_handledEventOrder.removeAt(0));
    }
    return true;
  }
}

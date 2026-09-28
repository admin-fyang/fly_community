/// Android 后台实时消息本地通知服务。
///
/// 本服务只负责把“已经成功写入 SQLite 的 Centrifugo 消息事件”转换为
/// Android 系统通知。它不建立连接、不处理消息一致性，也不承担离线推送职责。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/log_util.dart';
import '../enums/message_type.dart';
import '../local/app_settings_storage.dart';
import '../local/session_storage.dart';
import '../models/im_api_models.dart';
import 'im_event_reducer.dart';
import 'notification_branding_service.dart';

/// 点击消息通知后需要打开的会话。
class LocalMessageNotificationTap {
  const LocalMessageNotificationTap({required this.conversationId});

  final String conversationId;
}

/// Android 通知栏展示所需的最小、无平台依赖数据。
@visibleForTesting
class LocalMessageNotificationContent {
  const LocalMessageNotificationContent({
    required this.messageId,
    required this.conversationId,
    required this.title,
    required this.body,
  });

  final String messageId;
  final String conversationId;
  final String title;
  final String body;
}

class AndroidLocalNotificationService {
  AndroidLocalNotificationService(this._storage, this._settingsStorage);

  static const _channel = MethodChannel('com.fly.chat/local_notifications');
  static const _messageChannelId = 'message';
  static const _smallIcon = 'ic_notification';

  final SessionStorage _storage;
  final AppSettingsStorage _settingsStorage;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final _tapController =
      StreamController<LocalMessageNotificationTap>.broadcast();

  bool _initialized = false;
  bool _permissionRequested = false;

  Stream<LocalMessageNotificationTap> get taps => _tapController.stream;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 后台消息使用 flutter_local_notifications 展示。
  ///
  /// small icon 必须来自 APK drawable；系统配置的网络 Logo 会由
  /// [NotificationBrandingService] 转为本地 PNG，作为通知 large icon 展示。
  Future<void> showMessage(LocalMessageNotificationContent content) async {
    if (!_isAndroid) return;
    await initialize();
    try {
      final largeIcon = await _largeIcon();
      await _notifications.show(
        id: _stableNotificationId(content.messageId),
        title: content.title,
        body: content.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannelId,
            '聊天消息',
            channelDescription: '私聊、群聊和频道的新消息通知',
            icon: _smallIcon,
            largeIcon: largeIcon,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
            category: AndroidNotificationCategory.message,
          ),
        ),
        payload: jsonEncode({'conversation_id': content.conversationId}),
      );
      LogUtil.d(
        'action=displayed message_id=${content.messageId} '
        'conversation_id=${content.conversationId}',
        tag: 'IM notification',
      );
    } catch (error) {
      LogUtil.d('action=display-failed error=$error', tag: 'IM notification');
    }
  }

  Future<AndroidBitmap<Object>?> _largeIcon() async {
    if (!Get.isRegistered<NotificationBrandingService>()) return null;
    final path = await Get.find<NotificationBrandingService>()
        .resolveLargeIconPath();
    if (path == null || path.isEmpty) return null;
    return FilePathAndroidBitmap(path);
  }

  Future<void> playDefaultMessageSound() async {
    if (!_isAndroid) return;
    await initialize();
    try {
      await _channel.invokeMethod<void>('playMessageSound');
    } catch (error) {
      LogUtil.d('action=sound-failed error=$error', tag: 'IM notification');
    }
  }

  Future<void> vibrateShort() async {
    if (!_isAndroid) return;
    await initialize();
    try {
      await _channel.invokeMethod<void>('vibrateShort');
    } catch (error) {
      LogUtil.d('action=vibrate-failed error=$error', tag: 'IM notification');
    }
  }

  Future<void> openMessageChannelSettings() async {
    if (!_isAndroid) return;
    await initialize();
    await _channel.invokeMethod<void>('openMessageChannelSettings');
  }

  /// 初始化通知插件，并保留原生通道负责声音、震动和通知设置跳转。
  Future<void> initialize() async {
    if (!_isAndroid || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handlePlatformCall);

    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
        ),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
    } catch (error) {
      LogUtil.d(
        'action=plugin-initialize-failed error=$error',
        tag: 'IM notification',
      );
    }

    try {
      await _channel.invokeMethod<void>('initialize');
      final initialConversationId = await _channel.invokeMethod<String>(
        'consumeInitialConversationId',
      );
      _emitTap(initialConversationId);
      LogUtil.d('action=initialized', tag: 'IM notification');
    } catch (error) {
      // 原生辅助通道失败不影响 flutter_local_notifications 展示消息通知。
      LogUtil.d(
        'action=native-initialize-failed error=$error',
        tag: 'IM notification',
      );
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final conversationId = decoded is Map
          ? decoded['conversation_id']?.toString()
          : null;
      _emitTap(conversationId);
    } catch (_) {
      LogUtil.d('action=tap-invalid-payload', tag: 'IM notification');
    }
  }

  /// Android 13+ 首次登录后请求通知权限；旧版本会直接返回已授权状态。
  Future<void> ensurePermission() async {
    if (!_isAndroid || _permissionRequested) return;
    _permissionRequested = true;
    await initialize();
    final before = await Permission.notification.status;
    final after = before.isGranted
        ? before
        : await Permission.notification.request();
    LogUtil.d('action=permission result=${after.name}', tag: 'IM notification');
  }

  /// 仅处理实时链路的新消息；HTTP Sync 和本机写穿事件不会补发系统通知。
  ///
  /// [applyResult.changed] 为 false 说明 event_id 已处理过，必须跳过，防止
  /// Centrifugo Recovery 或重复 Publication 产生重复通知。
  Future<void> handlePersistedRealtimeEvent(
    Map<String, dynamic> event,
    ImEventApplyResult? applyResult,
  ) async {
    if (!_isAndroid ||
        applyResult?.changed != true ||
        event['event_type']?.toString() != 'message_created' ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    final user = await _storage.readUser();
    if (user == null) return;
    final settings = await _settingsStorage.readNotificationSettings();
    final content = buildContent(
      event: event,
      currentUserId: user.id,
      settings: settings,
    );
    if (content == null) return;
    await showMessage(content);
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'notificationTapped') return;
    final arguments = call.arguments;
    final conversationId = arguments is Map
        ? arguments['conversation_id']?.toString()
        : null;
    _emitTap(conversationId);
  }

  void _emitTap(String? conversationId) {
    final value = conversationId?.trim() ?? '';
    if (value.isEmpty) return;
    _tapController.add(LocalMessageNotificationTap(conversationId: value));
  }

  /// 从服务端权威消息快照构造通知文案，不读取 Widget 或页面状态。
  static LocalMessageNotificationContent? buildContent({
    required Map<String, dynamic> event,
    required String currentUserId,
    required NotificationSettingsSnapshot settings,
  }) {
    final payload = _object(event['payload']);
    final rawMessage = _object(payload['message']);
    final messageId =
        rawMessage['message_id']?.toString().trim() ??
        event['message_id']?.toString().trim() ??
        '';
    final conversationId =
        rawMessage['conversation_id']?.toString().trim() ??
        event['conversation_id']?.toString().trim() ??
        '';
    if (messageId.isEmpty || conversationId.isEmpty) return null;

    final dto = ImMessageDto.fromJson({
      ...rawMessage,
      'message_id': messageId,
      'conversation_id': conversationId,
    });
    if (dto.senderId == currentUserId) return null;

    final conversation = _object(payload['conversation']);
    if (!settings.privateEnabled) {
      return null;
    }
    if (_bool(conversation['is_muted'] ?? payload['is_muted']) == true) {
      return null;
    }

    final senderName = dto.senderName?.trim().isNotEmpty == true
        ? dto.senderName!.trim()
        : '新消息';
    final summary = settings.previewEnabled ? _messageSummary(dto) : '你收到一条新消息';
    return LocalMessageNotificationContent(
      messageId: messageId,
      conversationId: conversationId,
      title: senderName,
      body: summary,
    );
  }

  static String _messageSummary(ImMessageDto message) {
    if (message.messageType == MessageType.text ||
        message.messageType == MessageType.system) {
      final text = message.bodyText.trim();
      return text.isEmpty ? '你收到一条新消息' : text;
    }
    final label = message.messageType.previewLabel;
    return label.isEmpty ? '你收到一条新消息' : '[$label]';
  }
}

/// 与 Kotlin `String.hashCode() and Int.MAX_VALUE` 保持一致。
int _stableNotificationId(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

Map<String, dynamic> _object(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

bool? _bool(Object? value) => switch (value) {
  true || 1 || '1' || 'true' => true,
  false || 0 || '0' || 'false' => false,
  _ => null,
};

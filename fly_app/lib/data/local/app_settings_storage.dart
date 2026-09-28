/// 应用本地设置持久化。
///
/// 保存通知设置的本地缓存以及当前设备专属的展示偏好。
///
/// 私聊和通知预览由设置 Controller 与后端同步后写入此缓存；
/// in_app、声音、振动等字段只属于当前设备。本类不发起网络请求，也不保存凭证。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../enums/theme_mode_type.dart';

/// 聊天背景的内置资源。
enum ChatBackgroundType {
  patternSvg,
  patternPng;

  String get assetPath => switch (this) {
    ChatBackgroundType.patternSvg => 'assets/icons/pattern.svg',
    ChatBackgroundType.patternPng => 'assets/image/pattern_soft.png',
  };
}

/// 通知和声音设置快照。
class NotificationSettingsSnapshot {
  const NotificationSettingsSnapshot({
    this.privateEnabled = true,
    this.previewEnabled = true,
    this.inAppSoundEnabled = true,
    this.inAppVibrateEnabled = true,
    this.inAppPreviewEnabled = true,
  });

  final bool privateEnabled;
  final bool previewEnabled;
  final bool inAppSoundEnabled;
  final bool inAppVibrateEnabled;
  final bool inAppPreviewEnabled;
}

/// 聊天展示设置快照。
class ChatSettingsSnapshot {
  const ChatSettingsSnapshot({
    this.textSize = 16,
    this.background = ChatBackgroundType.patternSvg,
    this.showAvatar = true,
    this.twoLinePreview = false,
  });

  final double textSize;
  final ChatBackgroundType background;
  final bool showAvatar;
  final bool twoLinePreview;
}

/// SharedPreferences 的唯一设置读写入口。
class AppSettingsStorage {
  AppSettingsStorage({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _themeKey = 'settings.theme.mode';
  static const _notificationPrefix = 'settings.notification.';
  static const _chatPrefix = 'settings.chat.';

  final Future<SharedPreferences> _preferences;

  /// 后台通知 Isolate 在读取主进程刚保存的通知偏好前刷新本地缓存。
  Future<void> reload() async => (await _preferences).reload();

  Future<ThemeModeType> readThemeMode() async {
    final raw = (await _preferences).getString(_themeKey);
    return ThemeModeType.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => ThemeModeType.light,
    );
  }

  Future<void> saveThemeMode(ThemeModeType mode) async {
    final saved = await (await _preferences).setString(_themeKey, mode.name);
    if (!saved) throw StateError('主题设置保存失败');
  }

  Future<NotificationSettingsSnapshot> readNotificationSettings() async {
    final p = await _preferences;
    return NotificationSettingsSnapshot(
      privateEnabled: p.getBool('${_notificationPrefix}private') ?? true,
      previewEnabled: p.getBool('${_notificationPrefix}preview') ?? true,
      inAppSoundEnabled:
          p.getBool('${_notificationPrefix}in_app_sound') ?? true,
      inAppVibrateEnabled:
          p.getBool('${_notificationPrefix}in_app_vibrate') ?? true,
      inAppPreviewEnabled:
          p.getBool('${_notificationPrefix}in_app_preview') ?? true,
    );
  }

  Future<void> saveNotificationFlag(String key, bool value) =>
      _saveBool('$_notificationPrefix$key', value);

  Future<ChatSettingsSnapshot> readChatSettings() async {
    final p = await _preferences;
    final rawBackground = p.getString('${_chatPrefix}background');
    final background = ChatBackgroundType.values.firstWhere(
      (value) => value.name == rawBackground,
      orElse: () => ChatBackgroundType.patternSvg,
    );
    return ChatSettingsSnapshot(
      textSize: (p.getDouble('${_chatPrefix}text_size') ?? 16).clamp(12, 30),
      background: background,
      showAvatar: p.getBool('${_chatPrefix}show_avatar') ?? true,
      twoLinePreview: p.getBool('${_chatPrefix}two_line_preview') ?? false,
    );
  }

  Future<void> saveChatTextSize(double value) async {
    final saved = await (await _preferences).setDouble(
      '${_chatPrefix}text_size',
      value.clamp(12, 30),
    );
    if (!saved) throw StateError('文字大小保存失败');
  }

  Future<void> saveChatBackground(ChatBackgroundType value) =>
      _saveString('${_chatPrefix}background', value.name);

  Future<void> saveChatFlag(String key, bool value) =>
      _saveBool('$_chatPrefix$key', value);

  Future<void> _saveBool(String key, bool value) async {
    final saved = await (await _preferences).setBool(key, value);
    if (!saved) throw StateError('本地设置保存失败');
  }

  Future<void> _saveString(String key, String value) async {
    final saved = await (await _preferences).setString(key, value);
    if (!saved) throw StateError('本地设置保存失败');
  }
}

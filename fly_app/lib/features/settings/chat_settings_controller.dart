/// 当前设备聊天展示设置的响应式状态源。
///
/// 设置页只负责上报用户操作；聊天页与会话列表统一订阅本控制器，避免
/// SharedPreferences 已保存但实际页面仍使用硬编码默认值。
library;

import 'package:get/get.dart';

import '../../data/local/app_settings_storage.dart';
import '../../shared/utils/app_toast.dart';

/// 管理聊天展示偏好，并负责将每次变更持久化到当前设备。
class ChatSettingsController extends GetxController {
  ChatSettingsController(this._storage);

  final AppSettingsStorage _storage;

  final textSize = 16.0.obs;
  final background = ChatBackgroundType.patternSvg.obs;
  final showAvatar = true.obs;
  final twoLinePreview = false.obs;

  double _savedTextSize = 16;

  @override
  void onInit() {
    super.onInit();
    _restore();
  }

  /// 启动时恢复本机设置；读取失败时保留安全默认值。
  Future<void> _restore() async {
    try {
      final value = await _storage.readChatSettings();
      textSize.value = value.textSize;
      _savedTextSize = value.textSize;
      background.value = value.background;
      showAvatar.value = value.showAvatar;
      twoLinePreview.value = value.twoLinePreview;
    } catch (_) {
      AppToast.warning('聊天设置读取失败，已使用默认值');
    }
  }

  /// 滑动期间只更新响应式预览，松手后再写入本地存储。
  void previewTextSize(double value) {
    textSize.value = value.clamp(12, 30).toDouble();
  }

  Future<void> saveTextSize(double value) async {
    final next = value.clamp(12, 30).toDouble();
    textSize.value = next;
    try {
      await _storage.saveChatTextSize(next);
      _savedTextSize = next;
    } catch (_) {
      textSize.value = _savedTextSize;
      AppToast.error('文字大小保存失败，请重试');
    }
  }

  Future<void> selectBackground(ChatBackgroundType value) async {
    final previous = background.value;
    background.value = value;
    try {
      await _storage.saveChatBackground(value);
    } catch (_) {
      background.value = previous;
      AppToast.error('聊天背景保存失败，请重试');
    }
  }

  Future<void> setShowAvatar(bool value) async {
    final previous = showAvatar.value;
    showAvatar.value = value;
    try {
      await _storage.saveChatFlag('show_avatar', value);
    } catch (_) {
      showAvatar.value = previous;
      AppToast.error('设置保存失败，请重试');
    }
  }

  Future<void> setTwoLinePreview(bool value) async {
    final previous = twoLinePreview.value;
    twoLinePreview.value = value;
    try {
      await _storage.saveChatFlag('two_line_preview', value);
    } catch (_) {
      twoLinePreview.value = previous;
      AppToast.error('设置保存失败，请重试');
    }
  }
}

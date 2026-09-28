/// 用户主动操作成功后的统一轻量反馈入口。
///
/// 仅由 UI 在操作已被确认成功后调用。网络同步、后台重试、实时连接和
/// 生命周期变化必须使用页面状态，不调用本入口；失败优先在当前表单内展示。
/// 复用现有顶部提示的主题、无障碍和 Overlay 生命周期，避免创建第二套样式。
library;

import 'app_toast.dart';

abstract final class AppFeedback {
  /// 顶部显示成功图标及文案，2 秒后自动消失。
  static void show(String message) => AppToast.show(
    message,
    type: AppToastType.success,
    duration: const Duration(seconds: 2),
  );
}

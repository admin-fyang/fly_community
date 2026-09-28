/// 系统通知类型枚举。
///
/// 决定通知列表项左侧图标（好友请求或系统通知）。
library;

import 'package:flutter/material.dart';

/// 系统通知类型(决定左侧图标)
enum NotificationKind {
  friendRequest(Icons.person_add_alt),
  system(Icons.notifications_none);

  const NotificationKind(this.icon);
  final IconData icon;
}

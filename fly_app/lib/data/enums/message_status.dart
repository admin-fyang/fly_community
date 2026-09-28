/// 消息发送状态枚举。
///
/// 仅自己发送的消息使用，驱动气泡右下角的状态图标（发送中/已发送/已读/失败）。
library;

import 'package:flutter/material.dart';

/// 消息发送状态（仅自己发送的消息使用）
///
/// 作为独立状态驱动气泡右下角的状态图标。
enum MessageStatus {
  sending, // 发送中
  sent, // 已发送/服务端已接收（单勾）
  read, // 已读（双勾）
  failed; // 失败

  /// 状态对应的气泡角标图标
  IconData? get icon {
    switch (this) {
      case MessageStatus.sending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.read:
        return Icons.done_all;
      case MessageStatus.failed:
        return Icons.error_outline;
    }
  }
}

/// 按对端的单调回执游标计算自己消息的展示状态。
///
/// 本地的发送中/失败事实优先于服务端回执；对方消息不显示
/// 发送状态，因此原样返回。
MessageStatus resolveMessageReceiptStatus({
  required MessageStatus current,
  required bool isMine,
  required int? seq,
  required int lastReadSeq,
}) {
  if (!isMine || seq == null || seq <= 0) return current;
  if (current == MessageStatus.sending || current == MessageStatus.failed) {
    return current;
  }
  if (seq <= lastReadSeq) return MessageStatus.read;
  return MessageStatus.sent;
}

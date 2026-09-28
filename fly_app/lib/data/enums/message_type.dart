/// 消息类型枚举。
///
/// 社区版仅处理基础单聊消息与撤回、系统提示,
/// 并提供会话列表预览文案 / 图标的统一映射。
library;

import 'package:flutter/material.dart';

/// 消息类型
///
/// 用于会话列表预览与聊天气泡渲染。
/// 非文本消息在会话预览里用「图标 + 类型名」高亮显示（品牌色）。
enum MessageType {
  text,
  image,
  file,
  recall,
  system;

  /// 会话预览文案（文本/系统返回空，直接用正文）
  String get previewLabel {
    switch (this) {
      case MessageType.text:
      case MessageType.system:
      case MessageType.recall:
        return '';
      case MessageType.image:
        return '图片';
      case MessageType.file:
        return '文件';
    }
  }

  /// 会话预览前导图标（文本/系统/撤回无图标）
  IconData? get previewIcon {
    switch (this) {
      case MessageType.text:
      case MessageType.system:
      case MessageType.recall:
        return null;
      case MessageType.image:
        return Icons.photo_outlined;
      case MessageType.file:
        return Icons.insert_drive_file_outlined;
    }
  }

  /// 非文本消息在预览中用品牌色高亮
  bool get isMedia =>
      this != MessageType.text &&
      this != MessageType.system &&
      this != MessageType.recall;
}

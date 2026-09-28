/// 聊天输入区模式
///
/// 第一阶段只切换 UI 状态，不实现真实录音/表情/发送逻辑。
enum ChatInputMode {
  text, // 文本输入
  more, // 多功能面板
  emoji; // 表情面板

  /// 是否处于展开面板态(多功能面板或表情面板)
  bool get isPanelOpen =>
      this == ChatInputMode.more || this == ChatInputMode.emoji;
}

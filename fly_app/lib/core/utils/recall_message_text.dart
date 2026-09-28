/// 生成撤回消息的安全展示文案。
///
/// 撤回后的原正文可能仍存在于历史响应中，因此展示层只能根据发送者身份和
/// 发送者身份重新生成提示，不能直接显示消息正文。
String recallMessageText({required bool isMine}) {
  if (isMine) return '你撤回了一条消息';
  return '对方撤回了一条消息';
}

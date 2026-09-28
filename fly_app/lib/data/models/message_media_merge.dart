/// 消息媒体瞬态展示字段归并。
///
/// 服务端字段始终以 [incoming] 为准；本地图片只负责跨越 HTTP、
/// 实时事件与历史刷新之间的短暂显示窗口，避免远程封面尚未解码时退回占位图。
library;

import '../enums/message_type.dart';
import 'message_model.dart';

MessageModel mergeTransientMediaState(
  MessageModel current,
  MessageModel incoming,
) {
  if (incoming.type != MessageType.image) {
    return incoming;
  }
  if (current.attachments.isEmpty) return incoming;
  if (incoming.attachments.isEmpty) {
    return incoming.copyWith(attachments: current.attachments);
  }
  final attachments = <MessageAttachment>[];
  for (var index = 0; index < incoming.attachments.length; index++) {
    final next = incoming.attachments[index];
    if (index >= current.attachments.length) {
      attachments.add(next);
      continue;
    }
    final previous = current.attachments[index];
    attachments.add(
      next.copyWith(
        localPreviewPath: next.localPreviewPath ?? previous.localPreviewPath,
        localPreviewBytes:
            next.localPreviewBytes ?? previous.localPreviewBytes,
        localMediaPath: next.localMediaPath ?? previous.localMediaPath,
        localMediaBytes: next.localMediaBytes ?? previous.localMediaBytes,
      ),
    );
  }
  return incoming.copyWith(attachments: attachments);
}

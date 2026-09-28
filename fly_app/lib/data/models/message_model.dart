/// 消息数据模型。
///
/// 社区版消息模型承载基础单聊消息、引用和发送状态。
/// 以及发送状态与引用回复。第一阶段由 Mock 驱动。
library;

import '../enums/message_status.dart';
import '../enums/message_type.dart';

/// 普通消息附件的完整展示快照。
///
/// 服务端消息、SQLite 历史和本地待发送气泡都使用同一结构，避免多附件消息
/// 在 UI 层退化为只读取第一项。
class MessageAttachment {
  const MessageAttachment({
    required this.resourceId,
    this.resourceUrl,
    this.thumbnailResourceId,
    this.thumbnailUrl,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.durationMs,
    this.width,
    this.height,
    this.waveform = const [],
    this.localPreviewPath,
    this.localPreviewBytes,
    this.localMediaPath,
    this.localMediaBytes,
  });

  final String resourceId;
  final String? resourceUrl;
  final String? thumbnailResourceId;
  final String? thumbnailUrl;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final List<double> waveform;
  final String? localPreviewPath;
  final List<int>? localPreviewBytes;

  /// 待发送媒体的原文件。视频封面只负责气泡展示，播放必须读取这里的原视频。
  /// 原生端优先保存私有路径；Web 端暂存字节并在预览页生成可回收的 Blob URL。
  final String? localMediaPath;
  final List<int>? localMediaBytes;

  String? get displayUrl {
    final thumbnail = thumbnailUrl?.trim();
    if (thumbnail != null && thumbnail.isNotEmpty) return thumbnail;
    final resource = resourceUrl?.trim();
    return resource == null || resource.isEmpty ? null : resource;
  }

  String? get durationText {
    final milliseconds = durationMs;
    if (milliseconds == null) return null;
    final seconds = (milliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  MessageAttachment copyWith({
    String? resourceId,
    String? resourceUrl,
    String? thumbnailResourceId,
    String? thumbnailUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    List<double>? waveform,
    String? localPreviewPath,
    List<int>? localPreviewBytes,
    String? localMediaPath,
    List<int>? localMediaBytes,
  }) => MessageAttachment(
    resourceId: resourceId ?? this.resourceId,
    resourceUrl: resourceUrl ?? this.resourceUrl,
    thumbnailResourceId: thumbnailResourceId ?? this.thumbnailResourceId,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    mimeType: mimeType ?? this.mimeType,
    durationMs: durationMs ?? this.durationMs,
    width: width ?? this.width,
    height: height ?? this.height,
    waveform: waveform ?? this.waveform,
    localPreviewPath: localPreviewPath ?? this.localPreviewPath,
    localPreviewBytes: localPreviewBytes ?? this.localPreviewBytes,
    localMediaPath: localMediaPath ?? this.localMediaPath,
    localMediaBytes: localMediaBytes ?? this.localMediaBytes,
  );
}

/// 引用消息的紧凑预览。
///
/// 这里只保存绘制引用卡片所需的数据，不复制完整附件，也不依赖原消息已加载。
class ReplyPreview {
  const ReplyPreview({
    required this.kind,
    this.resourceId,
    this.thumbnailResourceId,
    this.previewUrl,
    this.width,
    this.height,
    this.durationMs,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.name,
    this.address,
    this.sharedUserId,
    this.displayName,
    this.avatarUrl,
  });

  final MessageType kind;
  final String? resourceId;
  final String? thumbnailResourceId;
  final String? previewUrl;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? name;
  final String? address;
  final String? sharedUserId;
  final String? displayName;
  final String? avatarUrl;
}

/// 引用回复的独立快照。
///
/// [messageId]/[seq] 仅用于本地定位；卡片本身始终由 [summary]/[preview]
/// 独立渲染，禁止把查询原消息作为显示前置条件。
class ReplyQuote {
  const ReplyQuote({
    required this.senderName,
    String? summary,
    String? text,
    this.snapshotVersion = 1,
    this.messageId,
    this.seq,
    this.senderId,
    this.messageType = MessageType.text,
    this.isAvailable = true,
    this.unavailableReason,
    this.preview,
    this.attachmentCount = 0,
  }) : summary = summary ?? text ?? '';

  final int snapshotVersion;
  final String? messageId;
  final int? seq;
  final String? senderId;
  final String senderName;
  final MessageType messageType;
  final bool isAvailable;
  final String? unavailableReason;
  final String summary;
  final ReplyPreview? preview;
  final int attachmentCount;

  /// 兼容现有输入栏和 Mock；新代码应优先使用 [summary]。
  String get text => summary;

  ReplyQuote recalled() => ReplyQuote(
    snapshotVersion: snapshotVersion,
    messageId: messageId,
    seq: seq,
    senderId: senderId,
    senderName: senderName,
    messageType: messageType,
    isAvailable: false,
    unavailableReason: 'recalled',
    summary: '原消息已撤回',
    attachmentCount: attachmentCount,
  );
}

/// 消息模型
///
/// 第一阶段由 Mock 驱动，字段覆盖气泡需要渲染的全部形态：
/// 文本 / 图片占位 / 语音 / 引用回复 / 系统消息，以及发送状态。
class MessageModel {
  const MessageModel({
    required this.id,
    required this.type,
    required this.isMine,
    required this.time,
    this.conversationId,
    this.clientMsgId,
    this.seq,
    this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    this.text = '',
    this.status = MessageStatus.sent,
    this.sendError,
    this.imageUrl,
    this.attachments = const [],
    this.reply,
    this.fileName,
    this.fileMeta,
  });

  final String id;
  final MessageType type;
  final String? conversationId;

  /// 客户端生成的幂等 ID；本地 sending/failed 与服务端消息据此归并。
  final String? clientMsgId;
  final int? seq;

  /// 是否自己发送（决定左右对齐与配色）
  final bool isMine;
  final DateTime time;

  final String? senderId;

  /// 发送者昵称（群聊对方消息显示）
  final String? senderName;

  /// 后端统一返回的发送者头像快照；群成员退群后仍可直接渲染。
  final String? senderAvatarUrl;

  final String text;

  /// 发送状态（仅自己消息有意义）
  final MessageStatus status;

  /// 仅用于本地待发送消息的用户可读失败原因；服务端确认或重试开始时清除。
  final String? sendError;

  /// 图片占位地址（为空时用色块占位）
  final String? imageUrl;

  /// 图片、视频和文件的完整附件列表，顺序与服务端 sort_order 一致。
  final List<MessageAttachment> attachments;

  /// 引用回复内容
  final ReplyQuote? reply;

  // ===== 卡片类消息附加字段 =====
  /// 文件名 / 文件副信息(如「4.2 MB • PDF」)
  final String? fileName;
  final String? fileMeta;


  /// 是否系统消息(居中灰字提示)
  bool get isSystem => type == MessageType.system;

  /// 是否撤回消息(居中弱化提示)
  bool get isRecall => type == MessageType.recall;

  MessageModel copyWith({
    String? id,
    MessageType? type,
    String? conversationId,
    String? clientMsgId,
    bool clearClientMsgId = false,
    int? seq,
    bool? isMine,
    DateTime? time,
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
    String? text,
    MessageStatus? status,
    String? sendError,
    bool clearSendError = false,
    String? imageUrl,
    List<MessageAttachment>? attachments,
    ReplyQuote? reply,
    String? fileName,
    String? fileMeta,
  }) {
    return MessageModel(
      id: id ?? this.id,
      type: type ?? this.type,
      conversationId: conversationId ?? this.conversationId,
      clientMsgId: clearClientMsgId ? null : clientMsgId ?? this.clientMsgId,
      seq: seq ?? this.seq,
      isMine: isMine ?? this.isMine,
      time: time ?? this.time,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      text: text ?? this.text,
      status: status ?? this.status,
      sendError: clearSendError ? null : sendError ?? this.sendError,
      imageUrl: imageUrl ?? this.imageUrl,
      attachments: attachments ?? this.attachments,
      reply: reply ?? this.reply,
      fileName: fileName ?? this.fileName,
      fileMeta: fileMeta ?? this.fileMeta,
    );
  }
}

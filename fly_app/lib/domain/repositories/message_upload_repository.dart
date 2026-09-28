library;

import 'package:dio/dio.dart';

import '../../data/models/im_api_models.dart';

enum MessageUploadMode { single, multipart }

class UploadedPartCheckpoint {
  const UploadedPartCheckpoint({
    required this.partNumber,
    required this.etag,
    required this.size,
  });

  final int partNumber;
  final String etag;
  final int size;

  Map<String, dynamic> toJson() => {
    'part_number': partNumber,
    'etag': etag,
    'size': size,
  };

  factory UploadedPartCheckpoint.fromJson(Map<String, dynamic> json) =>
      UploadedPartCheckpoint(
        partNumber: int.tryParse(json['part_number']?.toString() ?? '') ?? 0,
        etag: json['etag']?.toString() ?? '',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
      );
}

/// SQLite 中可恢复的 Multipart 会话快照；服务端 ListParts 始终具有最终权威。
class MessageUploadCheckpoint {
  const MessageUploadCheckpoint({
    required this.mode,
    required this.resourceId,
    this.uploadId,
    this.partSize,
    this.totalParts,
    this.expiresAt,
    this.uploadedParts = const [],
  });

  final MessageUploadMode mode;
  final String resourceId;
  final String? uploadId;
  final int? partSize;
  final int? totalParts;
  final int? expiresAt;
  final List<UploadedPartCheckpoint> uploadedParts;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'resource_id': resourceId,
    if (uploadId != null) 'upload_id': uploadId,
    if (partSize != null) 'part_size': partSize,
    if (totalParts != null) 'total_parts': totalParts,
    if (expiresAt != null) 'expires_at': expiresAt,
    'uploaded_parts': uploadedParts.map((item) => item.toJson()).toList(),
  };

  factory MessageUploadCheckpoint.fromJson(Map<String, dynamic> json) =>
      MessageUploadCheckpoint(
        mode: json['mode']?.toString() == 'multipart'
            ? MessageUploadMode.multipart
            : MessageUploadMode.single,
        resourceId: json['resource_id']?.toString() ?? '',
        uploadId: json['upload_id']?.toString(),
        partSize: int.tryParse(json['part_size']?.toString() ?? ''),
        totalParts: int.tryParse(json['total_parts']?.toString() ?? ''),
        expiresAt: int.tryParse(json['expires_at']?.toString() ?? ''),
        uploadedParts: (json['uploaded_parts'] is List
                ? json['uploaded_parts'] as List
                : const [])
            .whereType<Map>()
            .map(
              (item) => UploadedPartCheckpoint.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(),
      );
}

class MessageFileUploadProgress {
  const MessageFileUploadProgress({
    required this.mode,
    required this.sent,
    required this.total,
  });

  final MessageUploadMode mode;
  final int sent;
  final int total;
}

class MessageUploadPausedException implements Exception {
  const MessageUploadPausedException();
}

abstract interface class MessageUploadRepository {
  Future<MessageAttachmentDto> uploadMessageFile(
    MessageUploadFile file, {
    ProgressCallback? onProgress,
    MessageUploadCheckpoint? checkpoint,
    Future<void> Function(MessageUploadCheckpoint checkpoint)? onCheckpoint,
    void Function(MessageFileUploadProgress progress)? onFileProgress,
    CancelToken? cancelToken,
    bool Function()? isPaused,
  });
}

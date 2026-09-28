/// 聊天附件上传仓储实现。
///
/// 小文件继续使用单次预签名 PUT；大文件严格遵循服务端 S3 Multipart 协议，
/// 每次恢复先用 ListParts 覆盖本地快照，只补传服务端确认缺失的分片。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_paths.dart';
import '../../domain/repositories/message_upload_repository.dart';
import '../models/im_api_models.dart';
import '../network/object_storage_client.dart';

class MessageUploadRepositoryImpl implements MessageUploadRepository {
  const MessageUploadRepositoryImpl(this._client, this._storageClient);

  final ApiClient _client;
  final ObjectStorageClient _storageClient;

  @override
  Future<MessageAttachmentDto> uploadMessageFile(
    MessageUploadFile file, {
    ProgressCallback? onProgress,
    MessageUploadCheckpoint? checkpoint,
    Future<void> Function(MessageUploadCheckpoint checkpoint)? onCheckpoint,
    void Function(MessageFileUploadProgress progress)? onFileProgress,
    CancelToken? cancelToken,
    bool Function()? isPaused,
  }) async {
    var current = checkpoint;
    final existing = current;
    if (existing != null && existing.mode == MessageUploadMode.multipart) {
      try {
        final remote = await _readMultipart(existing.resourceId);
        if (remote.status == 'completed') {
          final completed = remote.completed;
          if (completed == null) {
            throw const ApiException(
              code: 'MULTIPART_COMPLETED_RESPONSE_INVALID',
              message: '已完成的分片上传缺少资源地址',
            );
          }
          return _completedAttachment(file, completed);
        }
        current = remote.checkpoint;
        await onCheckpoint?.call(remote.checkpoint);
      } on ApiException catch (error) {
        if (error.code != 'FILE_UPLOAD_EXPIRED' || error.statusCode != 410) {
          rethrow;
        }
        // 只有明确的 410 + FILE_UPLOAD_EXPIRED 才允许丢弃旧会话并重新初始化。
        current = null;
      }
    }

    if (current == null || current.mode == MessageUploadMode.single) {
      final credential = await _createCredential(file);
      if (credential.uploadMode != 'multipart') {
        return _uploadSingle(
          file,
          credential,
          onProgress: onProgress,
          onFileProgress: onFileProgress,
        );
      }
      current = _checkpointFromCredential(credential);
      await onCheckpoint?.call(current);
    }

    return _uploadMultipart(
      file,
      current,
      onProgress: onProgress,
      onCheckpoint: onCheckpoint,
      onFileProgress: onFileProgress,
      cancelToken: cancelToken,
      isPaused: isPaused,
    );
  }

  Future<MessageUploadCredential> _createCredential(MessageUploadFile file) =>
      _client.post<MessageUploadCredential>(
        ApiPaths.messageUploadCredentials,
        data: {
          'filename': file.filename,
          'size': file.size,
          'mime_type': file.mimeType,
        },
        decoder: (data) => MessageUploadCredential.fromJson(_jsonObject(data)),
      );

  Future<MessageAttachmentDto> _uploadSingle(
    MessageUploadFile file,
    MessageUploadCredential credential, {
    ProgressCallback? onProgress,
    void Function(MessageFileUploadProgress progress)? onFileProgress,
  }) async {
    onFileProgress?.call(
      MessageFileUploadProgress(
        mode: MessageUploadMode.single,
        sent: 0,
        total: file.size,
      ),
    );
    await _storageClient.put(
      uploadUrl: credential.uploadUrl,
      headers: credential.headers,
      bytes: _asUint8List(file.bytes),
      onSendProgress: (sent, total) {
        onProgress?.call(sent, total);
        onFileProgress?.call(
          MessageFileUploadProgress(
            mode: MessageUploadMode.single,
            sent: sent,
            total: total > 0 ? total : file.size,
          ),
        );
      },
    );

    final completed = await _client.post<CompletedMessageUpload>(
      ApiPaths.completeUpload(credential.resourceId),
      decoder: (data) => CompletedMessageUpload.fromJson(_jsonObject(data)),
    );
    return _completedAttachment(file, completed);
  }

  Future<MessageAttachmentDto> _uploadMultipart(
    MessageUploadFile file,
    MessageUploadCheckpoint checkpoint, {
    ProgressCallback? onProgress,
    Future<void> Function(MessageUploadCheckpoint checkpoint)? onCheckpoint,
    void Function(MessageFileUploadProgress progress)? onFileProgress,
    CancelToken? cancelToken,
    bool Function()? isPaused,
  }) async {
    final uploadId = checkpoint.uploadId?.trim() ?? '';
    final partSize = checkpoint.partSize ?? 0;
    final totalParts = checkpoint.totalParts ?? 0;
    if (uploadId.isEmpty || partSize <= 0 || totalParts <= 0) {
      throw const ApiException(
        code: 'MULTIPART_CREDENTIAL_INVALID',
        message: '分片上传凭证格式不正确',
      );
    }
    final bytes = _asUint8List(file.bytes);
    final uploaded = <int, UploadedPartCheckpoint>{
      for (final part in checkpoint.uploadedParts)
        if (part.partNumber > 0 && part.etag.isNotEmpty) part.partNumber: part,
    };

    void publishProgress(int sent) {
      final safeSent = sent.clamp(0, file.size);
      onProgress?.call(safeSent, file.size);
      onFileProgress?.call(
        MessageFileUploadProgress(
          mode: MessageUploadMode.multipart,
          sent: safeSent,
          total: file.size,
        ),
      );
    }

    var completedBytes = uploaded.values.fold<int>(
      0,
      (sum, part) => sum + part.size,
    );
    publishProgress(completedBytes);

    for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
      if (uploaded.containsKey(partNumber)) continue;
      if (isPaused?.call() == true || cancelToken?.isCancelled == true) {
        throw const MessageUploadPausedException();
      }
      final credential = await _readPartCredential(
        checkpoint.resourceId,
        uploadId,
        partNumber,
      );
      final start = (partNumber - 1) * partSize;
      final end = (start + partSize).clamp(0, bytes.length);
      if (start < 0 || start >= end || end > bytes.length) {
        throw const ApiException(
          code: 'MULTIPART_RANGE_INVALID',
          message: '本地视频分片范围无效',
        );
      }
      final partBytes = Uint8List.sublistView(bytes, start, end);
      late final String? etag;
      try {
        etag = await _storageClient.put(
          uploadUrl: credential.uploadUrl,
          headers: credential.headers,
          bytes: partBytes,
          cancelToken: cancelToken,
          onSendProgress: (sent, _) => publishProgress(completedBytes + sent),
        );
      } on ApiException catch (error) {
        if (error.code == 'STORAGE_UPLOAD_PAUSED') {
          throw const MessageUploadPausedException();
        }
        rethrow;
      }
      final normalizedEtag = etag?.trim() ?? '';
      if (normalizedEtag.isEmpty) {
        throw const ApiException(
          code: 'MULTIPART_ETAG_MISSING',
          message: '对象存储未返回分片 ETag，请检查 CORS ExposeHeaders',
        );
      }
      final part = UploadedPartCheckpoint(
        partNumber: partNumber,
        etag: normalizedEtag,
        size: partBytes.length,
      );
      uploaded[partNumber] = part;
      completedBytes += partBytes.length;
      checkpoint = MessageUploadCheckpoint(
        mode: MessageUploadMode.multipart,
        resourceId: checkpoint.resourceId,
        uploadId: uploadId,
        partSize: partSize,
        totalParts: totalParts,
        expiresAt: checkpoint.expiresAt,
        uploadedParts: uploaded.values.toList()
          ..sort((left, right) => left.partNumber.compareTo(right.partNumber)),
      );
      await onCheckpoint?.call(checkpoint);
      publishProgress(completedBytes);
    }

    if (isPaused?.call() == true) {
      throw const MessageUploadPausedException();
    }
    final parts = uploaded.values.toList()
      ..sort((left, right) => left.partNumber.compareTo(right.partNumber));
    if (parts.length != totalParts) {
      throw const ApiException(
        code: 'MULTIPART_PARTS_INCOMPLETE',
        message: '文件分片尚未上传完整',
      );
    }
    final completed = await _client.post<CompletedMessageUpload>(
      ApiPaths.completeMultipartUpload(checkpoint.resourceId),
      data: {
        'upload_id': uploadId,
        'parts': [
          for (final part in parts)
            {'part_number': part.partNumber, 'etag': part.etag},
        ],
      },
      decoder: (data) => CompletedMessageUpload.fromJson(_jsonObject(data)),
    );
    publishProgress(file.size);
    return _completedAttachment(file, completed);
  }

  Future<_MultipartRemoteState> _readMultipart(String resourceId) =>
      _client.get<_MultipartRemoteState>(
        ApiPaths.multipartUpload(resourceId),
        decoder: (data) => _MultipartRemoteState.fromJson(_jsonObject(data)),
      );

  Future<_MultipartPartCredential> _readPartCredential(
    String resourceId,
    String uploadId,
    int partNumber,
  ) async {
    final response = await _client.post<_MultipartCredentialsResponse>(
      ApiPaths.multipartPartCredentials(resourceId),
      data: {
        'upload_id': uploadId,
        'part_numbers': [partNumber],
      },
      decoder: (data) =>
          _MultipartCredentialsResponse.fromJson(_jsonObject(data)),
    );
    for (final part in response.parts) {
      if (part.partNumber == partNumber) return part;
    }
    throw const ApiException(
      code: 'MULTIPART_PART_CREDENTIAL_MISSING',
      message: '服务端未返回所需的分片上传地址',
    );
  }

  MessageUploadCheckpoint _checkpointFromCredential(
    MessageUploadCredential credential,
  ) {
    final checkpoint = MessageUploadCheckpoint(
      mode: MessageUploadMode.multipart,
      resourceId: credential.resourceId,
      uploadId: credential.uploadId,
      partSize: credential.partSize,
      totalParts: credential.totalParts,
      expiresAt: credential.expiresAt,
    );
    if (checkpoint.resourceId.isEmpty ||
        checkpoint.uploadId?.isNotEmpty != true ||
        (checkpoint.partSize ?? 0) <= 0 ||
        (checkpoint.totalParts ?? 0) <= 0) {
      throw const ApiException(
        code: 'MULTIPART_CREDENTIAL_INVALID',
        message: '服务端返回的分片上传凭证不完整',
      );
    }
    return checkpoint;
  }

  MessageAttachmentDto _completedAttachment(
    MessageUploadFile file,
    CompletedMessageUpload completed,
  ) {
    if (completed.resourceId.isEmpty || completed.url.isEmpty) {
      throw const ApiException(
        code: 'UPLOAD_COMPLETED_RESPONSE_INVALID',
        message: '上传完成响应缺少资源标识或访问地址',
      );
    }
    return MessageAttachmentDto(
      resourceId: completed.resourceId,
      url: completed.url,
      filename: file.filename,
      size: file.size,
      mimeType: file.mimeType,
    );
  }
}

class _MultipartPartCredential {
  const _MultipartPartCredential({
    required this.partNumber,
    required this.uploadUrl,
    required this.headers,
  });

  final int partNumber;
  final String uploadUrl;
  final Map<String, String> headers;

  factory _MultipartPartCredential.fromJson(Map<String, dynamic> json) =>
      _MultipartPartCredential(
        partNumber: int.tryParse(json['part_number']?.toString() ?? '') ?? 0,
        uploadUrl: json['upload_url']?.toString() ?? '',
        headers: _stringMap(json['headers']),
      );
}

class _MultipartCredentialsResponse {
  const _MultipartCredentialsResponse({required this.parts});
  final List<_MultipartPartCredential> parts;

  factory _MultipartCredentialsResponse.fromJson(Map<String, dynamic> json) =>
      _MultipartCredentialsResponse(
        parts: (json['parts'] is List ? json['parts'] as List : const [])
            .whereType<Map>()
            .map(
              (item) => _MultipartPartCredential.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(),
      );
}

class _MultipartRemoteState {
  const _MultipartRemoteState({
    required this.status,
    required this.checkpoint,
    this.completed,
  });

  final String status;
  final MessageUploadCheckpoint checkpoint;
  final CompletedMessageUpload? completed;

  factory _MultipartRemoteState.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString() ?? 'uploading';
    final checkpoint = MessageUploadCheckpoint(
      mode: MessageUploadMode.multipart,
      resourceId: json['resource_id']?.toString() ?? '',
      uploadId: json['upload_id']?.toString(),
      partSize: int.tryParse(json['part_size']?.toString() ?? ''),
      totalParts: int.tryParse(json['total_parts']?.toString() ?? ''),
      expiresAt: int.tryParse(json['expires_at']?.toString() ?? ''),
      uploadedParts:
          (json['uploaded_parts'] is List
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
    final url = json['resource_url']?.toString();
    return _MultipartRemoteState(
      status: status,
      checkpoint: checkpoint,
      completed: status == 'completed' && url != null && url.isNotEmpty
          ? CompletedMessageUpload(
              resourceId: checkpoint.resourceId,
              url: url,
              status: status,
            )
          : null,
    );
  }
}

/// SQLite 原生文件读取结果已经是 Uint8List，直接复用可避免大视频上传前
/// 再复制一份同等大小的 Dart 堆内存；Web 普通 List 才执行必要转换。
Uint8List _asUint8List(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('data 必须为 JSON 对象');
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
  );
}

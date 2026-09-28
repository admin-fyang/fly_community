/// 头像选择与直传流程的数据实体。
library;

import 'dart:typed_data';

/// 已在客户端完成校验、可提交上传的头像文件。
class AvatarUploadFile {
  const AvatarUploadFile({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  final String filename;
  final String mimeType;
  final Uint8List bytes;

  int get size => bytes.lengthInBytes;
}

/// 服务端签发的对象存储直传凭证。
class AvatarUploadCredential {
  const AvatarUploadCredential({
    required this.resourceId,
    required this.uploadUrl,
    required this.headers,
    required this.expiresIn,
  });

  final String resourceId;
  final String uploadUrl;
  final Map<String, String> headers;
  final int expiresIn;

  factory AvatarUploadCredential.fromJson(Map<String, dynamic> json) {
    try {
      final resourceId = json['resource_id'];
      final uploadUrl = json['upload_url'];
      final headers = json['headers'];
      final expiresIn = json['expires_in'];
      if (resourceId is! String ||
          uploadUrl is! String ||
          headers is! Map ||
          expiresIn is! int) {
        throw const FormatException('头像上传凭证缺少必填字段');
      }
      return AvatarUploadCredential(
        resourceId: resourceId,
        uploadUrl: uploadUrl,
        headers: headers.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
        expiresIn: expiresIn,
      );
    } catch (_) {
      throw const FormatException('头像上传凭证格式不正确');
    }
  }
}

/// 对象上传完成确认结果。
class CompletedUpload {
  const CompletedUpload({
    required this.resourceId,
    required this.url,
    required this.status,
  });

  final String resourceId;
  final String url;
  final String status;

  factory CompletedUpload.fromJson(Map<String, dynamic> json) {
    try {
      if (json['resource_id'] is! String ||
          json['url'] is! String ||
          json['status'] is! String) {
        throw const FormatException('上传完成结果缺少必填字段');
      }
      return CompletedUpload(
        resourceId: json['resource_id'] as String,
        url: json['url'] as String,
        status: json['status'] as String,
      );
    } catch (_) {
      throw const FormatException('上传完成结果格式不正确');
    }
  }
}

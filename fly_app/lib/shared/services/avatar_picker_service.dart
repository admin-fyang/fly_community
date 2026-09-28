/// 全局头像/图片选择服务。
///
/// 负责打开系统相机或相册、读取图片字节，并完成前端大小与类型校验。
library;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../../core/network/api_exception.dart';
import '../../domain/entities/avatar_upload.dart';

enum AvatarPickSource { camera, gallery }

abstract interface class AvatarPickerService {
  Future<AvatarUploadFile?> pick(AvatarPickSource source);
}

class ImagePickerAvatarService implements AvatarPickerService {
  ImagePickerAvatarService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  static const int maxBytes = 10 * 1024 * 1024;
  static const supportedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

  final ImagePicker _picker;

  @override
  Future<AvatarUploadFile?> pick(AvatarPickSource source) async {
    try {
      final selected = await _picker.pickImage(
        source:
            source == AvatarPickSource.camera
                ? ImageSource.camera
                : ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (selected == null) return null;

      final size = await selected.length();
      if (size < 1 || size > maxBytes) {
        throw const ApiException(
          code: 'AVATAR_SIZE_INVALID',
          message: '头像大小必须在 1 字节至 10MB 之间',
        );
      }

      final bytes = await selected.readAsBytes();
      final mimeType =
          selected.mimeType ??
          lookupMimeType(
            selected.name,
            headerBytes: bytes.take(32).toList(growable: false),
          );
      if (mimeType == null || !supportedMimeTypes.contains(mimeType)) {
        throw const ApiException(
          code: 'AVATAR_TYPE_INVALID',
          message: '头像仅支持 JPEG、PNG、WebP',
        );
      }

      return AvatarUploadFile(
        filename: _safeFilename(selected.name, mimeType),
        mimeType: mimeType,
        bytes: bytes,
      );
    } on ApiException {
      rethrow;
    } on PlatformException catch (error) {
      throw ApiException(
        code: 'AVATAR_PICK_FAILED',
        message: error.message ?? '无法打开相机或相册',
      );
    } catch (_) {
      throw const ApiException(
        code: 'AVATAR_PICK_FAILED',
        message: '头像选择失败，请重试',
      );
    }
  }

  String _safeFilename(String value, String mimeType) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && trimmed.length <= 191) return trimmed;
    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    return 'avatar.$extension';
  }
}

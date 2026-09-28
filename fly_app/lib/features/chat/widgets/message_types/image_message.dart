/// 图片消息组件。
///
/// 渲染图片气泡(第一阶段用色块占位)。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_sizes.dart';
import '../../../../data/models/message_model.dart';
import '../../../../data/services/im_pending_message_service.dart';
import 'media_grid.dart';

/// 图片消息内容(占位色块)
class ImageMessageContent extends StatelessWidget {
  const ImageMessageContent({
    super.key,
    required this.message,
    this.onTap,
    this.cachedBytes = const [],
    this.onDisplayed,
    this.uploadStates = const [],
    this.onUploadToggle,
  });

  final MessageModel message;
  final ValueChanged<int>? onTap;
  final List<Uint8List?> cachedBytes;
  final ValueChanged<int>? onDisplayed;
  final List<AttachmentUploadProgressState?> uploadStates;
  final ValueChanged<int>? onUploadToggle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: MediaAttachmentGrid(
        message: message,
        onTap: onTap,
        cachedBytes: cachedBytes,
        onImageDisplayed: onDisplayed,
        uploadStates: uploadStates,
        onUploadToggle: onUploadToggle,
      ),
    );
  }
}

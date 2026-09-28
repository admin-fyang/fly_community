/// 可编辑头像组件。
///
/// 统一头像本体、本地预览、右下角相机入口和上传进度遮罩。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../loading/app_cupertino_progress_indicator.dart';
import '../loading/app_loading_indicator.dart';
import 'app_avatar.dart';

class EditableAvatar extends StatelessWidget {
  const EditableAvatar({
    super.key,
    required this.size,
    this.name = '',
    this.imageUrl,
    this.localBytes,
    this.fallback,
    this.label,
    this.onTap,
    this.isUploading = false,
    this.progress = 0,
    this.borderWidth = 0,
    this.borderColor,
    this.cameraSize = 32,
    this.cameraIcon = Icons.photo_camera_outlined,
  });

  final double size;
  final String name;
  final String? imageUrl;
  final Uint8List? localBytes;
  final Widget? fallback;
  final String? label;
  final VoidCallback? onTap;
  final bool isUploading;
  final double progress;
  final double borderWidth;
  final Color? borderColor;
  final double cameraSize;
  final IconData cameraIcon;

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            padding: borderWidth > 0
                ? EdgeInsets.all(borderWidth / 2)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: borderWidth > 0
                  ? Border.all(
                      color:
                          borderColor ??
                          context.colorScheme.surfaceContainerHighest,
                      width: borderWidth,
                    )
                  : null,
            ),
            child: ClipOval(child: _content()),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: cameraSize,
              height: cameraSize,
              decoration: BoxDecoration(
                color: context.tokens.brand,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(cameraIcon, color: Colors.white, size: 18),
            ),
          ),
          if (isUploading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox.square(
                    dimension: 36,
                    child: progress > 0
                        ? AppCupertinoProgressIndicator(
                            progress: progress,
                            size: 36,
                            strokeWidth: 3,
                            color: Colors.white,
                          )
                        : const AppLoadingIndicator(
                            size: 24,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isUploading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          if (label != null) ...[
            const SizedBox(height: AppSizes.paddingLg),
            Text(
              label!,
              style: AppTextStyles.messageBody.copyWith(
                color: context.tokens.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _content() {
    final contentSize = size - borderWidth;
    if (localBytes != null) {
      return Image.memory(
        localBytes!,
        width: contentSize,
        height: contentSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (fallback != null) {
      return SizedBox(width: contentSize, height: contentSize, child: fallback);
    }
    return AppAvatar(imageUrl: imageUrl, name: name, size: contentSize);
  }
}

/// 文件消息组件。
///
/// 渲染文件气泡:类型图标 + 文件名 + 副信息。
library;

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extension.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/message_model.dart';
import '../../../../data/services/file_transfer_service.dart';

/// 文件消息内容:图标方块 + 文件名/副信息
class FileMessageContent extends StatelessWidget {
  const FileMessageContent({
    super.key,
    required this.message,
    required this.color,
    this.transferState = const FileTransferViewState(),
    this.onTap,
  });

  final MessageModel message;
  final Color color;
  final FileTransferViewState transferState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.tokens.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
      child: SizedBox(
        width: AppSizes.fileMessageWidth,
        child: Row(
          children: [
            Container(
              width: AppSizes.messageCardIconBox,
              height: AppSizes.messageCardIconBox,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
              ),
              child: Icon(Icons.description_outlined, color: brand, size: 22),
            ),
            const SizedBox(width: AppSizes.paddingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.fileName ?? '文件',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.messageBody.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusText(),
                    style: AppTextStyles.metadata.copyWith(
                      color: color.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() => switch (transferState.phase) {
    FileTransferPhase.downloading =>
      '下载中 ${(transferState.progress * 100).round()}%',
    FileTransferPhase.ready => '已下载 · 点击打开',
    FileTransferPhase.failed => '下载失败 · 点击重试',
    FileTransferPhase.idle => message.fileMeta ?? '点击下载',
  };
}

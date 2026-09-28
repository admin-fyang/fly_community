/// 聊天附件上传进度指示器。
///
/// 组件只负责展示 Presentation 层传入的状态并回传点击意图，不读取数据库、
/// 不访问上传服务。Multipart 上传中点击为暂停，暂停后点击为继续；Single
/// 上传没有点击回调，因此不会向用户暗示它具备断点续传能力。
library;

import 'package:flutter/material.dart';

import '../../../data/services/im_pending_message_service.dart';
import '../../../shared/widgets/loading/app_cupertino_progress_indicator.dart';
import '../../../shared/widgets/loading/app_loading_indicator.dart';

class AttachmentUploadIndicator extends StatelessWidget {
  const AttachmentUploadIndicator({
    super.key,
    required this.state,
    this.onToggle,
    this.compact = false,
  });

  final AttachmentUploadProgressState state;
  final VoidCallback? onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 42.0;
    final percent = (state.progress.clamp(0.0, 1.0) * 100).round();
    final paused = state.phase == AttachmentUploadPhase.paused;
    final processing = state.phase == AttachmentUploadPhase.processing;
    final preparing = state.phase == AttachmentUploadPhase.preparing;
    final waiting = state.phase == AttachmentUploadPhase.waiting;
    final indeterminate = preparing || waiting || processing;
    final interactive = state.canPause && onToggle != null && !indeterminate;

    final circle = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (indeterminate)
            AppLoadingIndicator(size: size, color: Colors.white)
          else
            AppCupertinoProgressIndicator(
              progress: state.progress,
              size: size,
              strokeWidth: compact ? 2.5 : 3,
              color: Colors.white,
              trackColor: Colors.white.withValues(alpha: 0.28),
              showPercentage: !paused,
            ),
          if (paused)
            Icon(
              Icons.play_arrow_rounded,
              size: compact ? 19 : 24,
              color: Colors.white,
            ),
        ],
      ),
    );

    // 百分比只在圆环中心显示。媒体格本身空间有限，再在圆环下方重复一次
    // 会与视频时长等信息争夺空间，也会让用户误以为存在两个上传任务。
    final content = circle;
    if (!interactive) return content;
    return Semantics(
      button: true,
      label: paused ? '继续上传，当前 $percent%' : '暂停上传，当前 $percent%',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(padding: const EdgeInsets.all(4), child: content),
      ),
    );
  }
}

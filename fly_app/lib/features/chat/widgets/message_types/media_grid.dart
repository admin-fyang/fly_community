/// 社区版图片消息的自适应多附件网格。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extension.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../data/enums/message_status.dart';
import '../../../../data/models/message_model.dart';
import '../../../../data/services/im_pending_message_service.dart';
import '../attachment_upload_indicator.dart';

class MediaAttachmentGrid extends StatelessWidget {
  const MediaAttachmentGrid({
    super.key,
    required this.message,
    this.onTap,
    this.cachedBytes = const [],
    this.onImageDisplayed,
    this.uploadStates = const [],
    this.onUploadToggle,
  });

  final MessageModel message;
  final ValueChanged<int>? onTap;
  final List<Uint8List?> cachedBytes;
  final ValueChanged<int>? onImageDisplayed;
  final List<AttachmentUploadProgressState?> uploadStates;
  final ValueChanged<int>? onUploadToggle;

  @override
  Widget build(BuildContext context) {
    final attachments = message.attachments.isNotEmpty
        ? message.attachments.take(9).toList()
        : <MessageAttachment>[
            MessageAttachment(resourceId: '', resourceUrl: message.imageUrl),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 媒体宽度跟随消息行的实际可用空间，不再使用 220/252 等固定尺寸。
        // 这与 flutter_chat_ui 的媒体组件一致：由聊天布局限制宽度，媒体自身
        // 只负责保持比例，并把最大高度控制在 300。
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width * 0.8;
        return _buildGrid(context, attachments, availableWidth);
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<MessageAttachment> attachments,
    double availableWidth,
  ) {
    const spacing = 2.0;
    const maxMediaHeight = AppSizes.mediaMaxHeight;
    final count = attachments.length;
    if (count == 1) {
      final attachment = attachments.first;
      final sourceWidth = attachment.width;
      final sourceHeight = attachment.height;
      final aspectRatio =
          sourceWidth != null &&
              sourceWidth > 0 &&
              sourceHeight != null &&
              sourceHeight > 0
          ? sourceWidth / sourceHeight
          : 4 / 3;
      var width = availableWidth;
      var height = width / aspectRatio;
      if (height > maxMediaHeight) {
        height = maxMediaHeight;
        width = height * aspectRatio;
      }
      return SizedBox(
        width: width,
        height: height,
        child: _tile(context, attachment, 0),
      );
    }
    if (count == 2) {
      return SizedBox(
        width: availableWidth,
        height: (availableWidth - spacing) / 2,
        child: Row(
          children: [
            Expanded(child: _tile(context, attachments[0], 0)),
            const SizedBox(width: spacing),
            Expanded(child: _tile(context, attachments[1], 1)),
          ],
        ),
      );
    }
    if (count == 3) {
      return SizedBox(
        width: availableWidth,
        height: (availableWidth * 2 / 3).clamp(0.0, maxMediaHeight).toDouble(),
        child: Row(
          children: [
            Expanded(child: _tile(context, attachments[0], 0)),
            const SizedBox(width: spacing),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _tile(context, attachments[1], 1)),
                  const SizedBox(height: spacing),
                  Expanded(child: _tile(context, attachments[2], 2)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final columns = count == 4 ? 2 : 3;
    final rows = (count / columns).ceil();
    final cellWidth = (availableWidth - (columns - 1) * spacing) / columns;
    final naturalHeight = rows * cellWidth + (rows - 1) * spacing;
    final gridHeight = naturalHeight.clamp(0.0, maxMediaHeight).toDouble();
    final cellHeight = (gridHeight - (rows - 1) * spacing) / rows;
    return SizedBox(
      width: availableWidth,
      height: gridHeight,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: count,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: cellWidth / cellHeight,
        ),
        itemBuilder: (context, index) =>
            _tile(context, attachments[index], index),
      ),
    );
  }

  Widget _tile(BuildContext context, MessageAttachment attachment, int index) {
    final remotePreviewUrl = attachment.displayUrl;
    final uploadState = index < uploadStates.length
        ? uploadStates[index]
        : null;
    final showUpload =
        message.status == MessageStatus.sending &&
        uploadState != null &&
        uploadState.phase != AttachmentUploadPhase.completed;
    // Telegram-iOS Night chat media placeholders are role-specific:
    // incoming = #1F1F1F mixed with 5% white (approximately #2A2A2A),
    // outgoing = white @ 20%. Keep Light behavior unchanged.
    final mediaPlaceholderColor = context.isDark
        ? (message.isMine ? const Color(0x33FFFFFF) : const Color(0xFF2A2A2A))
        : context.colorScheme.surfaceContainerHigh;
    return Material(
      color: mediaPlaceholderColor,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(index),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ProgressiveMediaThumbnail(
              key: ValueKey(
                '${message.clientMsgId ?? message.id}:$index',
              ),
              localBytes:
                  attachment.localPreviewBytes ??
                  (index < cachedBytes.length ? cachedBytes[index] : null),
              remoteUrl: remotePreviewUrl,
              onRemoteReady: onImageDisplayed == null
                  ? null
                  : () => onImageDisplayed!(index),
              placeholder: () => _placeholder(context),
            ),
            if (showUpload)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.38),
                  child: Center(
                    child: AttachmentUploadIndicator(
                      state: uploadState,
                      onToggle: uploadState.canPause && onUploadToggle != null
                          ? () => onUploadToggle!(index)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Center(
    child: Icon(
      Icons.image_outlined,
      size: 34,
      color: context.colorScheme.onSurfaceVariant,
    ),
  );

}

/// 本地图片到远程图片的单调切换组件。
///
/// 新消息快照可能先收到 URL、后完成网络图片解码。这里会保留最后一张有效
/// 本地封面，只有远程图片首帧已经进入 Flutter ImageCache 后才淡入覆盖，
/// 因而 HTTP、实时事件和历史刷新都不会制造“封面消失后又出现”的空帧。
class _ProgressiveMediaThumbnail extends StatefulWidget {
  const _ProgressiveMediaThumbnail({
    super.key,
    required this.localBytes,
    required this.remoteUrl,
    required this.placeholder,
    this.onRemoteReady,
  });

  final List<int>? localBytes;
  final String? remoteUrl;
  final Widget Function() placeholder;
  final VoidCallback? onRemoteReady;

  @override
  State<_ProgressiveMediaThumbnail> createState() =>
      _ProgressiveMediaThumbnailState();
}

class _ProgressiveMediaThumbnailState
    extends State<_ProgressiveMediaThumbnail> {
  Uint8List? _retainedLocalBytes;
  ImageProvider<Object>? _remoteProvider;
  ImageStream? _remoteStream;
  ImageStreamListener? _remoteListener;
  String? _resolvedRemoteUrl;
  bool _remoteReady = false;
  bool _didNotifyRemoteReady = false;

  @override
  void initState() {
    super.initState();
    _retainLocalBytes();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveRemoteIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ProgressiveMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _retainLocalBytes();
    if (oldWidget.remoteUrl != widget.remoteUrl) {
      _didNotifyRemoteReady = false;
      _resolveRemoteIfNeeded(force: true);
    }
  }

  void _retainLocalBytes() {
    final bytes = widget.localBytes;
    if (bytes != null && bytes.isNotEmpty) {
      _retainedLocalBytes = Uint8List.fromList(bytes);
    }
  }

  void _resolveRemoteIfNeeded({bool force = false}) {
    final url = widget.remoteUrl?.trim();
    if (!force && url == _resolvedRemoteUrl) return;
    _detachRemoteListener();
    _resolvedRemoteUrl = url;
    _remoteReady = false;
    _remoteProvider = null;
    if (url == null || url.isEmpty) return;

    final provider = NetworkImage(url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) {
        if (!mounted || _resolvedRemoteUrl != url) return;
        setState(() => _remoteReady = true);
        if (!_didNotifyRemoteReady) {
          _didNotifyRemoteReady = true;
          widget.onRemoteReady?.call();
        }
        stream.removeListener(listener);
        if (identical(_remoteListener, listener)) {
          _remoteStream = null;
          _remoteListener = null;
        }
      },
      onError: (_, __) {
        // 远程封面失败时继续显示已经可用的本地封面，不回退为空状态。
        stream.removeListener(listener);
        if (identical(_remoteListener, listener)) {
          _remoteStream = null;
          _remoteListener = null;
        }
      },
    );
    _remoteProvider = provider;
    _remoteStream = stream;
    _remoteListener = listener;
    stream.addListener(listener);
  }

  void _detachRemoteListener() {
    final stream = _remoteStream;
    final listener = _remoteListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _remoteStream = null;
    _remoteListener = null;
  }

  @override
  void dispose() {
    _detachRemoteListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = _retainedLocalBytes;
    final remote = _remoteProvider;
    if (local == null || local.isEmpty) {
      if (remote == null) return widget.placeholder();
      return Image(
        image: remote,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.placeholder(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          local,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => widget.placeholder(),
        ),
        if (remote != null)
          AnimatedOpacity(
            opacity: _remoteReady ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: Image(
              image: remote,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

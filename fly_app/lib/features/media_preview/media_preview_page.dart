/// 社区版图片全屏预览页。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:flychat/shared/widgets/loading/app_cupertino_progress_indicator.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/enums/message_type.dart';
import '../../data/models/message_model.dart';
import '../../shared/widgets/avatar/app_avatar.dart';
import 'media_preview_controller.dart';

class MediaPreviewPage extends StatefulWidget {
  const MediaPreviewPage({super.key});

  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<MediaPreviewPage>
    with SingleTickerProviderStateMixin {
  late final MediaPreviewController controller;
  late final ExtendedPageController _imagePages;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'media-preview');
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey = GlobalKey();
  late final AnimationController _zoomAnimation;
  Animation<double>? _zoom;
  VoidCallback? _zoomListener;
  bool _chromeVisible = true;
  Timer? _chromeTimer;

  @override
  void initState() {
    super.initState();
    controller = Get.find<MediaPreviewController>();
    final initial = controller.currentIndex.value;
    _imagePages = ExtendedPageController(
      initialPage: initial,
      pageSpacing: 24,
      shouldIgnorePointerWhenScrolling: false,
    );
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scheduleChromeHide();
  }

  @override
  void dispose() {
    _zoom?.removeListener(_zoomListener ?? () {});
    _chromeTimer?.cancel();
    _zoomAnimation.dispose();
    _imagePages.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      autofocus: true,
      focusNode: _keyboardFocus,
      onKeyEvent: _handleKey,
      child: AppPageScaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _imageGallery(),
            _chromeOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _chromeOverlay() => Obx(() {
    // 当前索引和保存进度驱动预览覆盖层。
    controller.currentIndex.value;
    controller.isSaving.value;
    controller.saveProgress.value;
    return IgnorePointer(
      ignoring: !_chromeVisible,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, right: 0, child: _topChrome()),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomChrome()),
          ],
        ),
      ),
    );
  });

  Widget _topChrome() => AppTopBar(
    height: 86,
    padding: EdgeInsets.zero,
    darkSurface: true,
    showStatus: false,
    child: Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          right: 8,
          top: 8,
          child: AppTopBarStatus(
            color: Colors.white,
            isReading: () => controller.isCurrentMediaLoading,
          ),
        ),
        Positioned(
          left: 16,
          top: 8,
          child: _roundAction(
            icon: Icons.close_rounded,
            tooltip: '关闭',
            onTap: () => Get.back<void>(),
          ),
        ),
        if (controller.attachments.length > 1)
          Positioned(
            left: 68,
            top: 18,
            child: Text(
              '${controller.currentIndex.value + 1}  /  ${controller.attachments.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Positioned(
          left: 82,
          right: 82,
          top: 54,
          child: Text(
            controller.currentFilename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bottomChrome() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2000000), Color(0x99000000), Color(0x00000000)],
          stops: [0, 0.58, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 34, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mediaActions(),
              if (controller.attachments.length > 1) ...[
                const SizedBox(height: 10),
                _pageDots(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaActions() {
    final itemContext = controller.currentItemContext;
    final name = itemContext.senderName?.trim().isNotEmpty == true
        ? itemContext.senderName!.trim()
        : '未知用户';
    final size = _formatBytes(controller.currentAttachment?.fileSize);
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              AppAvatar(
                name: name,
                imageUrl: itemContext.senderAvatarUrl,
                size: 24,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (size != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('•', style: TextStyle(color: Color(0xFF708499))),
                ),
                Flexible(
                  child: Text(
                    size,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF708499),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        _saveAction(),
      ],
    );
  }

  Widget _saveAction() {
    final saving = controller.isSaving.value;
    final progress = controller.saveProgress.value;
    return _roundAction(
      icon: Icons.download_rounded,
      tooltip: '下载',
      onTap: saving ? null : controller.saveCurrent,
      child: saving
          ? SizedBox.square(
              dimension: 20,
              child: progress > 0
                  ? AppCupertinoProgressIndicator(
                      progress: progress,
                      size: 20,
                      strokeWidth: 2,
                      color: Colors.white,
                    )
                  : const AppLoadingIndicator(size: 20, color: Colors.white),
            )
          : null,
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Widget? child,
    bool transparent = false,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: transparent ? Colors.transparent : const Color(0x4D2C3640),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: child ?? Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    ),
  );

  Widget _pageDots() {
    final count = math.min(controller.attachments.length, 5);
    final active = controller.attachments.length <= 5
        ? controller.currentIndex.value
        : ((controller.currentIndex.value * count) /
                  controller.attachments.length)
              .floor()
              .clamp(0, count - 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == active
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF2C3640),
            ),
          ),
      ],
    );
  }

  String? _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  void _onPageChanged(int index) {
    _showChromeTemporarily();
    controller.changePage(index);
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      _scheduleChromeHide();
    } else {
      _chromeTimer?.cancel();
    }
  }

  void _showChromeTemporarily() {
    if (mounted && !_chromeVisible) setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _chromeVisible) setState(() => _chromeVisible = false);
    });
  }

  Widget _imageGallery() {
    return ExtendedImageSlidePage(
      key: _slidePageKey,
      slideAxis: SlideAxis.vertical,
      slideType: SlideType.wholePage,
      resetPageDuration: const Duration(milliseconds: 220),
      // 只允许向下退出，向上拖动立即被约束回原点。
      slideOffsetHandler: (offset, {ExtendedImageSlidePageState? state}) =>
          Offset(0, math.max(0, offset.dy)),
      slideEndHandler:
          (
            offset, {
            ExtendedImageSlidePageState? state,
            ScaleEndDetails? details,
          }) {
            if (details == null) return offset.dy >= 120;
            final velocity = details.velocity.pixelsPerSecond.dy;
            return offset.dy >= 120 || velocity >= 800;
          },
      slidePageBackgroundHandler: (offset, size) {
        final opacity = (1 - offset.dy.abs() / (size.height * 0.55)).clamp(
          0.0,
          1.0,
        );
        return Colors.black.withValues(alpha: opacity);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleChrome,
        child: ExtendedImageGesturePageView.builder(
          controller: _imagePages,
          itemCount: controller.attachments.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) =>
              _imagePage(controller.attachments[index], index),
        ),
      ),
    );
  }

  Widget _imagePage(MessageAttachment attachment, int index) {
    return Obx(() {
      final bytes = controller.imageBytes(index);
      final error = controller.imageRestoreErrors[index];
      return _imageContent(attachment, index, bytes, error);
    });
  }

  Widget _imageContent(
    MessageAttachment attachment,
    int index,
    List<int>? bytes,
    String? restoreError,
  ) {
    GestureConfig commonConfig(ExtendedImageState state) => GestureConfig(
      inPageView: true,
      initialScale: 1,
      minScale: 1,
      animationMinScale: 0.9,
      maxScale: 5,
      animationMaxScale: 5.5,
      speed: 1,
      inertialSpeed: 100,
      initialAlignment: InitialAlignment.center,
      cacheGesture: false,
    );
    Widget? loadState(ExtendedImageState state) {
      final loading = state.extendedImageLoadState == LoadState.loading;
      // 图片回调可能发生在构建期，帧后通知控制器，避免构建中触发顶栏重建。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.reportImageLoading(index, loading);
      });
      switch (state.extendedImageLoadState) {
        case LoadState.loading:
          return const Center(child: AppLoadingIndicator(color: Colors.white));
        case LoadState.failed:
          return _mediaFailure(message: '图片加载失败', onRetry: state.reLoadImage);
        case LoadState.completed:
          return null;
      }
    }

    if (bytes != null && bytes.isNotEmpty) {
      return ExtendedImage.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableSlideOutPage: true,
        initGestureConfigHandler: commonConfig,
        onDoubleTap: _handleDoubleTap,
        loadStateChanged: loadState,
      );
    }
    final url = attachment.resourceUrl?.trim();
    if (url == null || url.isEmpty) {
      return _mediaFailure(
        message: restoreError ?? '正在恢复本地图片…',
        onRetry: () => controller.restoreImage(index),
      );
    }
    return ExtendedImage.network(
      url,
      cache: true,
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      enableSlideOutPage: true,
      initGestureConfigHandler: commonConfig,
      onDoubleTap: _handleDoubleTap,
      loadStateChanged: loadState,
    );
  }

  void _handleDoubleTap(ExtendedImageGestureState state) {
    final begin = state.gestureDetails?.totalScale ?? 1;
    final end = begin > 1 ? 1.0 : 2.5;
    _zoom?.removeListener(_zoomListener ?? () {});
    _zoomAnimation
      ..stop()
      ..reset();
    final pointer = state.pointerDownPosition;
    _zoom = _zoomAnimation.drive(Tween<double>(begin: begin, end: end));
    _zoomListener = () =>
        state.handleDoubleTap(scale: _zoom!.value, doubleTapPosition: pointer);
    _zoom!.addListener(_zoomListener!);
    _zoomAnimation.forward();
  }

  Widget _mediaFailure({
    required String message,
    required VoidCallback? onRetry,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 48,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('重新加载'),
            ),
          ],
        ],
      ),
    );
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Get.back<void>();
      return;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft &&
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft ? -1 : 1;
    final next = (controller.currentIndex.value + delta).clamp(
      0,
      controller.attachments.length - 1,
    );
    if (next == controller.currentIndex.value) return;
    _imagePages.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

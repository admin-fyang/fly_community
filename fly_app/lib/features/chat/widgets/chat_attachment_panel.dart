/// 聊天附件悬浮胶囊导航。
///
/// V7：
/// - 保留左下角纵向悬浮结构；
/// - 菜单以输入栏附件按钮为动画锚点，从按钮位置向上展开；
/// - 收起时反向缩回附件按钮，而不是从屏幕左边缘横向飞出；
/// - 支持纵向跟手拖动：展开后向下拖收起，隐藏后从附件按钮附近向上拖展开；
/// - 顶部保留圆角，底部两个角改为直角；
/// - 默认最多同时展示 6 个功能，超出后内部纵向滚动。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../data/enums/message_type.dart';
import '../chat_controller.dart';

class ChatAttachmentReferenceCapsuleMenu extends StatefulWidget {
  const ChatAttachmentReferenceCapsuleMenu({
    super.key,
    required this.controller,
    required this.visible,
    required this.maxHeight,
  });

  final ChatController controller;
  final bool visible;
  final double maxHeight;

  /// 顶部“收起”固定可见，不计入这里。
  static const int _visibleFunctionCount = 6;

  static const double _menuWidth = 74;
  static const double _itemHeight = 58;
  static const double _outerPadding = 5;
  static const double _topRadius = 28;
  static const double _bottomRadius = 10;
  static const double _selectedRadius = 21;

  /// 输入栏 `+` 按钮为 44x42。这里保留一块与按钮接近的透明手势热区，
  /// 菜单关闭后也能从该位置向上拖出导航。
  static const double _buttonHotZoneHeight = 48;

  /// 菜单完整展开后，菜单底部与附件按钮中心之间的视觉距离。
  /// flutter_chat_page 会把整个组件的底部对齐到附件按钮附近，因此这里
  /// 只需要控制菜单相对锚点向上的距离。
  static const double _anchorToMenuBottom = 35;

  /// 跟手拖动多少距离视作完整的 0 -> 1 动画进度。
  static const double _dragDistance = 150;

  /// 菜单横向位置与输入栏附件按钮并非完全同宽。动画收拢时将菜单宽度
  /// 轻微压缩到按钮尺寸附近，以产生“收入 + 按钮”的感觉。
  static const double _collapsedScaleX = 0.48;

  @override
  State<ChatAttachmentReferenceCapsuleMenu> createState() =>
      _ChatAttachmentReferenceCapsuleMenuState();
}

class _ChatAttachmentReferenceCapsuleMenuState
    extends State<ChatAttachmentReferenceCapsuleMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    //如果动画还是太快可以改成750
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 620),
    value: widget.visible ? 1 : 0,
  );

  bool _dragging = false;

  final ScrollController _functionScrollController = ScrollController();
  bool _showBottomScrollHint = true;

  ChatController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _functionScrollController.addListener(_handleFunctionScroll);
  }

  void _handleFunctionScroll() {
    if (!_functionScrollController.hasClients) return;

    final position = _functionScrollController.position;
    final shouldShow =
        position.maxScrollExtent > 0 && position.extentAfter > 8;

    if (shouldShow == _showBottomScrollHint || !mounted) return;
    setState(() => _showBottomScrollHint = shouldShow);
  }

  @override
  void didUpdateWidget(covariant ChatAttachmentReferenceCapsuleMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible || _dragging) return;
    _animateToVisibleState(widget.visible);
  }

  @override
  void dispose() {
    _functionScrollController
      ..removeListener(_handleFunctionScroll)
      ..dispose();
    _revealController.dispose();
    super.dispose();
  }

  Future<void> _animateToVisibleState(bool visible) async {
    if (visible) {
      await _revealController.animateTo(
        1,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    } else {
      await _revealController.animateTo(
        0,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _revealController.stop();
    _dragging = true;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    // 向上 dy < 0：展开；向下 dy > 0：收起。
    final next =
        _revealController.value -
            details.delta.dy / ChatAttachmentReferenceCapsuleMenu._dragDistance;
    _revealController.value = next.clamp(0.0, 1.0);
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _dragging = false;

    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldOpen = velocity < -360
        ? true
        : velocity > 360
        ? false
        : _revealController.value >= 0.5;

    if (shouldOpen) {
      if (!widget.visible) {
        controller.expandAttachmentMenu();
      } else {
        _animateToVisibleState(true);
      }
    } else {
      if (widget.visible) {
        controller.collapseAttachmentMenu();
      } else {
        _animateToVisibleState(false);
      }
    }
  }

  void _handleVerticalDragCancel() {
    _dragging = false;
    _animateToVisibleState(widget.visible);
  }

  List<_AttachmentEntry> _entries() {
    return <_AttachmentEntry>[
      if (controller.canUploadAttachments)
        const _AttachmentEntry(
          id: 'album',
          iconAsset: 'assets/icons/chat/image.svg',
          label: '相册',
          attachmentType: MessageType.image,
        ),
      if (controller.canUploadAttachments)
        const _AttachmentEntry(
          id: 'file',
          iconAsset: 'assets/icons/chat/file.svg',
          label: '文件',
          attachmentType: MessageType.file,
        ),
    ];
  }

  int _visibleCountFor(List<_AttachmentEntry> entries) {
    if (entries.isEmpty) return 0;

    final headerAndPadding =
        ChatAttachmentReferenceCapsuleMenu._itemHeight +
            ChatAttachmentReferenceCapsuleMenu._outerPadding * 2;

    final availableForList = (widget.maxHeight - headerAndPadding).clamp(
      ChatAttachmentReferenceCapsuleMenu._itemHeight,
      double.infinity,
    );

    final fitCount =
    (availableForList / ChatAttachmentReferenceCapsuleMenu._itemHeight)
        .floor();

    return fitCount
        .clamp(
      1,
      entries.length <
          ChatAttachmentReferenceCapsuleMenu._visibleFunctionCount
          ? entries.length
          : ChatAttachmentReferenceCapsuleMenu._visibleFunctionCount,
    )
        .toInt();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      controller.systemConfigRevision;
      final activeType = controller.pickingAttachmentType.value;
      final entries = _entries();
      final visibleCount = _visibleCountFor(entries);
      final listHeight =
          visibleCount * ChatAttachmentReferenceCapsuleMenu._itemHeight;
      final menuHeight =
          ChatAttachmentReferenceCapsuleMenu._outerPadding * 2 +
              ChatAttachmentReferenceCapsuleMenu._itemHeight +
              listHeight;
      final scrollable = entries.length > visibleCount;

      final anchorSpace =
          ChatAttachmentReferenceCapsuleMenu._anchorToMenuBottom +
              ChatAttachmentReferenceCapsuleMenu._buttonHotZoneHeight / 2;

      return SizedBox(
        width: ChatAttachmentReferenceCapsuleMenu._menuWidth,
        height: menuHeight + anchorSpace,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 关闭后仍在附件按钮附近保留透明热区。向上拖时直接驱动同一个
            // revealController，因此菜单会从按钮位置跟手长出来。
            if (!widget.visible || _revealController.value < 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height:
                ChatAttachmentReferenceCapsuleMenu._buttonHotZoneHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: _handleVerticalDragStart,
                  onVerticalDragUpdate: _handleVerticalDragUpdate,
                  onVerticalDragEnd: _handleVerticalDragEnd,
                  onVerticalDragCancel: _handleVerticalDragCancel,
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned(
              left: 0,
              bottom: anchorSpace,
              child: AnimatedBuilder(
                animation: _revealController,
                builder: (context, child) {
                  final progress = _revealController.value;
                  final eased = Curves.easeInOutCubic.transform(progress);

                  // 锚点位于菜单下方，即输入栏附件按钮所在位置。
                  // scaleY 让导航像从按钮向上生长；scaleX 只做轻微收束，
                  // 避免传统抽屉式的横向飞入感。
                  final scaleX =
                      ChatAttachmentReferenceCapsuleMenu._collapsedScaleX +
                          (1 -
                              ChatAttachmentReferenceCapsuleMenu
                                  ._collapsedScaleX) *
                              eased;
                  final scaleY = 0.045 + 0.955 * eased;

                  final anchor = Offset(
                    24,
                    menuHeight +
                        ChatAttachmentReferenceCapsuleMenu
                            ._anchorToMenuBottom,
                  );

                  final transform = Matrix4.identity()
                    ..translate(anchor.dx, anchor.dy)
                    ..scale(scaleX, scaleY)
                    ..translate(-anchor.dx, -anchor.dy);

                  return Transform(
                    transform: transform,
                    child: Opacity(
                      opacity: (progress * 1.7).clamp(0.0, 1.0),
                      child: IgnorePointer(
                        ignoring: progress < 0.92 && !_dragging,
                        child: child,
                      ),
                    ),
                  );
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: _handleVerticalDragStart,
                  onVerticalDragUpdate: _handleVerticalDragUpdate,
                  onVerticalDragEnd: _handleVerticalDragEnd,
                  onVerticalDragCancel: _handleVerticalDragCancel,
                  child: _buildCapsule(
                    context,
                    entries: entries,
                    activeType: activeType,
                    listHeight: listHeight,
                    scrollable: scrollable,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCapsule(
      BuildContext context, {
        required List<_AttachmentEntry> entries,
        required MessageType? activeType,
        required double listHeight,
        required bool scrollable,
      }) {
    final semantic = context.semanticColors;
    final communicationAllowed = controller.canSendMessage;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);

    // 按你的要求：只有顶部两个角保留圆角，底部完全直角。
    final radius = const BorderRadius.only(
      topLeft: Radius.circular(
        ChatAttachmentReferenceCapsuleMenu._topRadius,
      ),
      topRight: Radius.circular(
        ChatAttachmentReferenceCapsuleMenu._topRadius,
      ),
      bottomLeft: Radius.circular(
        ChatAttachmentReferenceCapsuleMenu._bottomRadius,
      ),
      bottomRight: Radius.circular(
        ChatAttachmentReferenceCapsuleMenu._bottomRadius,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.10),
              blurRadius: 20,
              spreadRadius: 5,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.11 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: ChatAttachmentReferenceCapsuleMenu._menuWidth,
              padding: const EdgeInsets.all(
                ChatAttachmentReferenceCapsuleMenu._outerPadding,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? semantic.surface.withValues(alpha: 0.90)
                    : Colors.white.withValues(alpha: 0.91),
                borderRadius: radius,
                border: Border.all(
                  width: hairline,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.075)
                      : Colors.white.withValues(alpha: 0.82),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReferenceCapsuleItem(
                    iconAsset: 'assets/icons/chat/arrow_down.svg',
                    label: '收起',
                    showLabel: false,
                    selected: true,
                    foreground: semantic.accent,
                    onTap: controller.collapseAttachmentMenu,
                  ),
                  if (entries.isNotEmpty)
                    SizedBox(
                      height: listHeight,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ListView.builder(
                              controller: _functionScrollController,
                              primary: false,
                              padding: EdgeInsets.zero,
                              clipBehavior: Clip.hardEdge,
                              physics: scrollable
                                  ? const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              )
                                  : const NeverScrollableScrollPhysics(),
                              itemCount: entries.length,
                              itemExtent:
                              ChatAttachmentReferenceCapsuleMenu._itemHeight,
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                return _ReferenceCapsuleItem(
                                  iconAsset: entry.iconAsset,
                                  label: entry.label,
                                  enabled: entry.enabled,
                                  loading:
                                  entry.attachmentType != null &&
                                      activeType == entry.attachmentType,
                                  foreground: entry.enabled && communicationAllowed
                                      ? semantic.textPrimary
                                      : semantic.textDisabled,
                                  onTap: entry.enabled
                                      ? () => _activate(entry)
                                      : null,
                                );
                              },
                            ),
                          ),

                          // 底部“还有内容”的玻璃提示层：
                          // 只在列表还能继续向下滚动时显示；到达底部后自动淡出。
                          if (scrollable)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 20,
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  opacity: _showBottomScrollHint ? 1 : 0,
                                  child: ClipRect(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 2,
                                        sigmaY: 2,
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              semantic.surface.withValues(
                                                alpha: 0.02,
                                              ),
                                              semantic.surface.withValues(
                                                alpha: isDark ? 0.72 : 0.66,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _activate(_AttachmentEntry entry) async {
    if (!entry.enabled) return;

    controller.collapseAttachmentMenu();

    final attachmentType = entry.attachmentType;
    if (attachmentType != null) {
      await controller.pickAndSendAttachment(attachmentType);
      return;
    }

  }
}

/// 参考图式导航项：图标在上，文字在下；普通态完全透明。
class _ReferenceCapsuleItem extends StatefulWidget {
  const _ReferenceCapsuleItem({
    required this.iconAsset,
    required this.label,
    required this.foreground,
    required this.onTap,
    this.enabled = true,
    this.loading = false,
    this.selected = false,
    this.showLabel = true,
  });

  final String iconAsset;
  final String label;
  final Color foreground;
  final VoidCallback? onTap;
  final bool enabled;
  final bool loading;
  final bool selected;
  final bool showLabel;

  @override
  State<_ReferenceCapsuleItem> createState() => _ReferenceCapsuleItemState();
}

class _ReferenceCapsuleItemState extends State<_ReferenceCapsuleItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || widget.loading || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canTap = widget.enabled && !widget.loading && widget.onTap != null;
    final highlighted = widget.selected || _pressed;
    final foreground = widget.selected ? semantic.accent : widget.foreground;

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.enabled ? widget.label : '${widget.label}，暂不可用',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: canTap ? (_) => _setPressed(true) : null,
        onTapCancel: canTap ? () => _setPressed(false) : null,
        onTapUp: canTap ? (_) => _setPressed(false) : null,
        onTap: canTap ? widget.onTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.965 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 2),
            /*decoration: BoxDecoration(
              color: highlighted
                  ? semantic.accent.withValues(
                      alpha: isDark
                          ? (widget.selected ? 0.20 : 0.14)
                          : (widget.selected ? 0.115 : 0.075),
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(
                ChatAttachmentReferenceCapsuleMenu._selectedRadius,
              ),
            ),*/
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 130),
                    child: widget.loading
                        ? SizedBox.square(
                      key: const ValueKey('loading'),
                      dimension: 20,
                      child: AppLoadingIndicator(
                        size: 20,
                        color: semantic.accent,
                      ),
                    )
                        : SvgPicture.asset(
                            widget.iconAsset,
                            key: ValueKey(widget.iconAsset),
                            width: widget.selected ? 23 : 21,
                            height: widget.selected ? 23 : 21,
                            colorFilter: ColorFilter.mode(
                              foreground,
                              BlendMode.srcIn,
                            ),
                          ),
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 10.5,
                        height: 1.0,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _AttachmentEntry {
  const _AttachmentEntry({
    required this.id,
    required this.iconAsset,
    required this.label,
    this.attachmentType,
  });

  final String id;
  final String iconAsset;
  final String label;
  final MessageType? attachmentType;

  bool get enabled => attachmentType != null;
}

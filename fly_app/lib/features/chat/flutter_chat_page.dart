/// 基于 flutter_chat_ui 的聊天详情页。
///
/// 保留既有顶栏、输入栏和工具面板，仅替换消息列表、基础气泡和滚动内核。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as flyer;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as flyer_ui;
import 'package:flutter_svg/svg.dart';
import 'package:flyer_chat_file_message/flyer_chat_file_message.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:get/get.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/time/system_clock.dart';
import '../../core/utils/date_time_util.dart';
import '../../data/enums/chat_input_mode.dart';
import '../../data/enums/message_status.dart';
import '../../data/enums/message_type.dart';
import '../../data/models/message_model.dart';
import '../../data/services/file_transfer_service.dart';
import '../../data/services/im_pending_message_service.dart';
import '../../data/services/system_time_service.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/avatar/app_avatar.dart';
import '../../shared/widgets/chat/chat_background.dart';
import '../../shared/widgets/empty/app_empty_state.dart';
import '../../shared/widgets/skeleton/app_skeleton.dart';
import '../settings/chat_settings_controller.dart';
import 'chat_controller.dart';
import 'chat_navigation.dart';
import 'chat_ui_design_adapter.dart';
import 'flyer_chat_controller.dart';
import 'widgets/chat_app_bar.dart';
import 'widgets/attachment_upload_indicator.dart';
import 'widgets/chat_attachment_panel.dart';
import 'widgets/chat_emoji_panel.dart';
import 'widgets/chat_reply_preview.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_context_menu.dart';
import 'widgets/message_input_bar.dart';

/// 新聊天页入口。
class FlutterChatPage extends StatefulWidget {
  const FlutterChatPage({super.key});

  @override
  State<FlutterChatPage> createState() => _FlutterChatPageState();
}

class _FlutterChatPageState extends State<FlutterChatPage> {
  Timer? _keyboardHandoffTimer;
  DateTime? _keyboardHandoffStartedAt;
  late final ChatRouteSession _routeSession = Get.find<ChatRouteSession>();
  late final String _conversationId = _routeSession.conversationId;
  late final ChatController controller = Get.find<ChatController>(
    tag: ChatRouteSession.controllerTagFor(_conversationId),
  );
  late final ChatSettingsController settingsController =
      Get.find<ChatSettingsController>();
  late final FlyerChatController flyerController = FlyerChatController(
    chatController: controller,
  );
  final ScrollController _messageScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_handleMessageScroll);
  }

  void _handleMessageScroll() {
    if (!_messageScrollController.hasClients) return;
    final position = _messageScrollController.position;
    // 新消息插入造成的程序化锚定不能把“正在浏览历史”误判成回到底部。
    // 只有用户实际滚动到末端时才重新开启最新消息已读上报。
    if (position.pixels > 48) {
      controller.updateViewportAtLatest(false);
    } else if (position.userScrollDirection != ScrollDirection.idle) {
      controller.updateViewportAtLatest(true);
    }
  }

  @override
  void dispose() {
    _keyboardHandoffTimer?.cancel();
    _messageScrollController.dispose();
    flyerController.dispose();
    _routeSession.deactivate(_conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return Obx(() {
      // 服务器时区变化后重新构建可见消息时间。
      Get.find<SystemTimeService>().revision.value;
      final mode = controller.inputMode.value;
      final keyboardTransitionPending =
          controller.keyboardTransitionPending.value;
      final keyboardTransitionSourceMode =
          controller.keyboardTransitionSourceMode.value;
      final attachmentMenuVisible = controller.attachmentMenuVisible.value;
      controller.keyboardHeightRevision.value;

      // 只有 Emoji 继续占用 Bottom Slot。附件入口已经改为聊天区左侧的
      // 悬浮纵向胶囊，不再改变底部高度。
      final panelOpen =
          mode == ChatInputMode.emoji;
      final transitionPanelVisible =
          keyboardTransitionPending &&
          keyboardTransitionSourceMode?.isPanelOpen == true;
      final panelHeight = controller.inputPanelHeight(
        keyboardHeight: keyboardBottom,
        // 等高占位期间不能记录尚在展开的键盘高度，否则空槽会逐帧变化。
        shouldRecordKeyboardHeight: !panelOpen && !keyboardTransitionPending,
      );
      // 自定义面板必须尽量复用“真实键盘高度”，不能为了容纳旧版两行宫格
      // 强行抬到 300+safeArea。否则实际 IME 只有 260~290px 时，
      // panel -> keyboard 交接的最后一帧仍会发生几十像素的高度跳变。
      // 新版胶囊导航可在较低高度下正常布局，因此这里只限制屏幕可用上限。
      final maximumPanelHeight =
          (MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).top -
                  kToolbarHeight -
                  96)
              .clamp(180.0, 420.0)
              .toDouble();
      final effectivePanelHeight = panelOpen || keyboardTransitionPending
          ? panelHeight.clamp(0.0, maximumPanelHeight).toDouble()
          : panelHeight;
      // panel -> keyboard 交接期间绝不能比旧面板更矮；如果新键盘实际更高，
      // 则允许占位随 viewInsets 向上增长，避免 IME 在最后几帧盖住输入栏。
      final reservedBottomHeight = keyboardTransitionPending
          ? (keyboardBottom > effectivePanelHeight
                ? keyboardBottom
                : effectivePanelHeight)
          : panelOpen
          ? effectivePanelHeight
          : keyboardBottom;
      if (keyboardTransitionPending && keyboardBottom > 0) {
        _scheduleKeyboardHandoff(
          keyboardBottom: keyboardBottom,
          expectedKeyboardHeight: controller.expectedKeyboardHeight,
        );
      } else if (!keyboardTransitionPending) {
        _resetKeyboardHandoffWatch();
      }
      final hasDismissibleInputLayer =
          panelOpen || keyboardTransitionPending || attachmentMenuVisible;
      final bottomSafe = MediaQuery.paddingOf(context).bottom;
      final floatingMenuBottom =
          reservedBottomHeight +
          62 +
          (reservedBottomHeight > 0 ? 0 : bottomSafe);
      return PopScope(
        canPop: !hasDismissibleInputLayer,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.collapseInputPanel();
        },
        child: AppPageScaffold(
          topContentGap: AppSizes.paddingLg,
          extendBodyBehindAppBar: true,
          readActivity: controller.pageReads,
          extendBody: true,
          resizeToAvoidBottomInset: false,
          appBar: ChatAppBar(controller: controller),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _messageList(context),
              // 悬浮附件导航的整个动画锚定在输入栏 `+` 按钮附近。
              // MessageInputBar：外层左 padding=6，附件按钮=44x42，按钮中心
              // 距左侧约 28px；纵向中心距 Bottom Slot 顶部约 27px。
              // 组件内部再向上保留 35px，使完整展开时仍保持原菜单位置。
              Positioned(
                left: 4,
                bottom:
                    reservedBottomHeight +
                    (reservedBottomHeight > 0 ? 3 : bottomSafe + 3),
                child: ChatAttachmentReferenceCapsuleMenu(
                  key: const ValueKey(
                    'attachment-reference-capsule-menu-v7-button-anchor',
                  ),
                  controller: controller,
                  visible: attachmentMenuVisible,
                  maxHeight:
                      (MediaQuery.sizeOf(context).height -
                              MediaQuery.paddingOf(context).top -
                              kToolbarHeight -
                              floatingMenuBottom -
                              12)
                          .clamp(160.0, 430.0)
                          .toDouble(),
                ),
              ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _replyPreview(context),
              _attachmentFeedback(context),
              if (controller.canSendMessage)
                MessageInputBar(controller: controller)
              else
                const SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: Text('当前仅允许好友之间私聊')),
                  ),
                ),
              // Bottom Slot 现在只服务系统键盘和 Emoji。附件功能已移到左侧
              // 悬浮胶囊，因此打开附件入口不会再改变消息列表高度。
              SizedBox(
                height: reservedBottomHeight,
                child: panelOpen
                    ? _inputPanel(context, mode, effectivePanelHeight)
                    : transitionPanelVisible
                    ? IgnorePointer(
                        child: _inputPanel(
                          context,
                          keyboardTransitionSourceMode ?? ChatInputMode.emoji,
                          effectivePanelHeight,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Android IME 展开期间 viewInsets 会逐帧变化。
  ///
  /// 这里不再使用“收到第一个非 0 inset 后 80ms 就交接”的策略，因为部分
  /// 厂商输入法的中间帧间隔会超过 80ms，导致 Emoji 占位提前释放。
  /// 已经记录过真实键盘高度时，只有当前 inset 接近目标高度才立即完成；
  /// 首次启动或输入法高度发生变化时，则要求 inset 在较长稳定窗口内不再变化。
  void _scheduleKeyboardHandoff({
    required double keyboardBottom,
    required double expectedKeyboardHeight,
  }) {
    _keyboardHandoffStartedAt ??= DateTime.now();
    _keyboardHandoffTimer?.cancel();

    final reachedExpected =
        expectedKeyboardHeight > 0 &&
        keyboardBottom >= expectedKeyboardHeight - 2;
    final observedInset = keyboardBottom;
    final delay = reachedExpected
        ? const Duration(milliseconds: 32)
        : const Duration(milliseconds: 220);

    _keyboardHandoffTimer = Timer(delay, () {
      if (!mounted || !controller.keyboardTransitionPending.value) return;

      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final view = views.first;
      final liveInset = view.viewInsets.bottom / view.devicePixelRatio;
      final targetReached =
          expectedKeyboardHeight > 0 && liveInset >= expectedKeyboardHeight - 2;
      final stable = (liveInset - observedInset).abs() < 1;
      final elapsed = DateTime.now().difference(
        _keyboardHandoffStartedAt ?? DateTime.now(),
      );

      // 有历史真实高度：到达目标后即可交接。
      // 无目标或输入法高度已改变：至少等待 500ms，并确认 inset 已稳定。
      if (targetReached ||
          (stable && elapsed >= const Duration(milliseconds: 500))) {
        controller.completeKeyboardTransition();
        _resetKeyboardHandoffWatch();
        return;
      }

      if (liveInset > 0) {
        _scheduleKeyboardHandoff(
          keyboardBottom: liveInset,
          expectedKeyboardHeight: expectedKeyboardHeight,
        );
      }
    });
  }

  void _resetKeyboardHandoffWatch() {
    _keyboardHandoffTimer?.cancel();
    _keyboardHandoffTimer = null;
    _keyboardHandoffStartedAt = null;
  }

  Widget _messageList(BuildContext context) {
    return Obx(() {
      final background = settingsController.background.value;
      // 在消息列表构建阶段订阅字号和头像开关，使当前打开的聊天即时刷新。
      settingsController.textSize.value;
      settingsController.showAvatar.value;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: controller.collapseInputPanel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ChatBackground(background: background),
            Obx(() {
              // 这里只等待初始数据投影，不参与任何滚动定位。SQLite 有历史时优先
              // 展示本地数据；无历史时等待首次服务端加载，避免先创建空列表后再
              // 插入整页消息触发额外滚动。
              flyerController.projectionRevision.value;
              final domainMessageCount = controller.messageSnapshot.length;
              final initialDataReady =
                  flyerController.isReady.value &&
                  controller.initialLocalLoadCompleted.value &&
                  (domainMessageCount > 0 ||
                      controller.initialLoadCompleted.value) &&
                  flyerController.messages.length == domainMessageCount;
              if (!initialDataReady) {
                return const _ChatMessageSkeleton();
              }
              flyerController.commitInitialProjection();
              return flyer_ui.Chat(
                currentUserId: flyerController.currentUserId.value,
                resolveUser: flyerController.resolveUser,
                userCache: flyerController.userCache,
                chatController: flyerController,
                backgroundColor: Colors.transparent,
                // flutter_chat_ui 只负责列表内核，视觉必须经过项目 token 适配；
                // 直接使用 ChatTheme.light/dark 会退回第三方示例 RoyalBlue 风格。
                theme: ChatUiDesignAdapter.themeOf(context),
                onMessageTap:
                    (context, message, {int index = 0, TapUpDetails? details}) {
                      if (details != null) {
                        _onMessageTap(context, message, details);
                      }
                    },
                onMessageLongPress:
                    (
                      context,
                      message, {
                      int index = 0,
                      LongPressStartDetails? details,
                    }) {
                      if (details != null) {
                        _onMessageLongPress(context, message, details);
                      }
                    },
                builders: flyer.Builders(
                  loadMoreBuilder: (_) => const SizedBox.shrink(),
                  composerBuilder: (_) => const SizedBox.shrink(),
                  emptyChatListBuilder: (_) =>
                      const Center(child: AppEmptyState(message: '暂无消息')),
                  chatAnimatedListBuilder: (context, itemBuilder) =>
                      flyer_ui.ChatAnimatedListReversed(
                        itemBuilder: itemBuilder,
                        scrollController: _messageScrollController,
                        topPadding:
                            appTopBarInset(context) + AppSizes.paddingLg,
                        bottomPadding: AppSizes.paddingLg,
                        handleSafeArea: true,
                        shouldScrollToEndWhenSendingMessage: true,
                        onEndReached: controller.loadOlderMessages,
                      ),
                  textMessageBuilder: _buildTextMessage,
                  imageMessageBuilder: _buildImageMessage,
                  fileMessageBuilder: _buildFileMessage,
                  customMessageBuilder: _buildCustomMessage,
                  systemMessageBuilder: _buildSystemMessage,
                  chatMessageBuilder: _buildMessageWrapper,
                  scrollToBottomBuilder: _buildScrollToBottom,
                ),
              );
            }),
          ],
        ),
      );
    });
  }

  Widget _buildTextMessage(
    BuildContext context,
    flyer.TextMessage message,
    int index, {
    required bool isSentByMe,
    flyer.MessageGroupStatus? groupStatus,
  }) {
    final domain = flyerController.domainMessage(message.id);
    if (domain != null) {
      return MessageBubble(
        message: domain,
        embeddedInChatLayout: true,
        messageTextSize: settingsController.textSize.value,
        groupPosition: ChatUiDesignAdapter.groupPositionOf(groupStatus),
        onReplyTap: _locateReply,
      );
    }

    // 投影切换的极短窗口内保留第三方回退渲染，避免消息瞬间消失。
    // 正常路径始终使用上方项目组件的真正行内元信息布局。
    return FlyerChatTextMessage(
      message: message,
      index: index,
      padding: const EdgeInsets.all(AppSizes.paddingItem),
      borderRadius: ChatUiDesignAdapter.bubbleRadius(
        isSentByMe: isSentByMe,
        groupPosition: ChatUiDesignAdapter.groupPositionOf(groupStatus),
      ),
      constraints: ChatUiDesignAdapter.messageConstraints(context),
      showTime: true,
      showStatus: isSentByMe,
      timeAndStatusPosition: flyer.TimeAndStatusPosition.end,
    );
  }

  Widget _buildSystemMessage(
    BuildContext context,
    flyer.SystemMessage message,
    int index, {
    required bool isSentByMe,
    flyer.MessageGroupStatus? groupStatus,
  }) {
    return _systemMessagePill(context, message.text, service: true);
  }

  /// 滚动到底按钮保留 40px 库标准尺寸，但向屏幕边缘收拢并移除 FAB 阴影。
  ///
  /// 默认右边距 16px 会与 85% 宽媒体消息的时间胶囊相交；右移 12px 后，
  /// 按钮仍保留安全边距，同时不再遮挡媒体元信息。
  Widget _buildScrollToBottom(
    BuildContext context,
    Animation<double> animation,
    VoidCallback onPressed,
  ) {
    final colors = context.colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          disabledElevation: 0,
          highlightElevation: 0,
          iconSize: 18,
        ),
      ),
      child: flyer_ui.ScrollToBottom(
        animation: animation,
        onPressed: () {
          onPressed();
          Future<void>.delayed(
            const Duration(milliseconds: 320),
            () => controller.updateViewportAtLatest(true),
          );
        },
        right: AppSizes.paddingXs,
        backgroundColor: context.isDark
            ? const Color(0xFF1C1C1D)
            : colors.surfaceContainerHigh.withValues(alpha: 0.94),
        foregroundColor: colors.onSurface,
        icon: SvgPicture.asset(
          'assets/icons/chat/arrow_down.svg',
          width: 18,
          height: 18,
          colorFilter: ColorFilter.mode(colors.onSurface, BlendMode.srcIn),
        ),
      ),
    );
  }

  Widget _buildImageMessage(
    BuildContext context,
    flyer.ImageMessage message,
    int index, {
    required bool isSentByMe,
    flyer.MessageGroupStatus? groupStatus,
  }) {
    final domain = flyerController.domainMessage(message.id);
    // 官方单图组件只表示一张远端图片。多附件和本地待上传预览继续使用
    // 原有内容组件，避免升级气泡外观时破坏九宫格与“先显示后上传”。
    if (domain == null || !_canUseFlyerImage(domain, message.source)) {
      return _buildRichMessage(
        message.id,
        groupPosition: ChatUiDesignAdapter.groupPositionOf(groupStatus),
      );
    }
    return FlyerChatImageMessage(
      message: message,
      index: index,
      borderRadius: ChatUiDesignAdapter.bubbleRadius(
        isSentByMe: isSentByMe,
        groupPosition: ChatUiDesignAdapter.groupPositionOf(groupStatus),
      ),
      constraints: ChatUiDesignAdapter.messageConstraints(
        context,
      ).copyWith(maxHeight: 300),
      errorBuilder: (_, __, ___) => _imageDecodeFallback(context),
      topWidget: domain.reply == null
          ? null
          : _replyQuote(context, domain, domain.reply!, onMedia: true),
    );
  }

  Widget _buildCustomMessage(
    BuildContext context,
    flyer.CustomMessage message,
    int index, {
    required bool isSentByMe,
    flyer.MessageGroupStatus? groupStatus,
  }) => _buildBusinessMessage(
    message.id,
    groupPosition: ChatUiDesignAdapter.groupPositionOf(groupStatus),
  );

  bool _canUseFlyerImage(MessageModel message, String source) {
    if (message.attachments.length > 1 ||
        message.status == MessageStatus.sending) {
      return false;
    }
    final attachment = message.attachments.isEmpty
        ? null
        : message.attachments.first;
    if (attachment == null ||
        attachment.width == null ||
        attachment.width! <= 0 ||
        attachment.height == null ||
        attachment.height! <= 0) {
      return false;
    }
    final uri = Uri.tryParse(source);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Widget _imageDecodeFallback(BuildContext context) => ColoredBox(
    color: context.colorScheme.surfaceContainerHigh,
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: context.colorScheme.onSurfaceVariant,
        size: 30,
      ),
    ),
  );

  Widget _buildFileMessage(
    BuildContext context,
    flyer.FileMessage message,
    int index, {
    required bool isSentByMe,
    flyer.MessageGroupStatus? groupStatus,
  }) => Obx(() {
    final domain = flyerController.domainMessage(message.id);
    final transfer = domain == null
        ? const FileTransferViewState()
        : controller.fileTransferState(domain);
    final upload = domain == null
        ? null
        : controller.attachmentUploadState(domain, 0);
    final showUpload =
        domain?.status == MessageStatus.sending &&
        upload != null &&
        upload.phase != AttachmentUploadPhase.completed;
    final bubble = ConstrainedBox(
      constraints: ChatUiDesignAdapter.messageConstraints(context),
      child: FlyerChatFileMessage(
        message: message,
        index: index,
        padding: const EdgeInsets.all(AppSizes.paddingItem),
        borderRadius: ChatUiDesignAdapter.bubbleRadius(
          isSentByMe: isSentByMe,
          groupPosition: ChatUiDesignAdapter.groupPositionOf(groupStatus),
        ),
        iconColor: showUpload ? Colors.transparent : null,
        topWidget: _fileBubbleTop(context, domain, transfer),
      ),
    );
    if (!showUpload) return bubble;
    return Stack(
      children: [
        bubble,
        Positioned.directional(
          textDirection: Directionality.of(context),
          start: 9,
          top: 0,
          bottom: 0,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.42),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AttachmentUploadIndicator(
                  state: upload,
                  compact: true,
                  onToggle: upload.canPause
                      ? () => controller.toggleAttachmentUpload(domain!, 0)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  });

  /// 官方文件气泡没有下载任务反馈；只在任务进行或失败时追加紧凑状态，
  /// 空闲/完成状态保持 local.dart 示例的原始视觉。
  Widget? _fileBubbleTop(
    BuildContext context,
    MessageModel? message,
    FileTransferViewState transfer,
  ) {
    if (message == null) return null;
    final widgets = <Widget>[];
    final reply = message.reply;
    if (reply != null) widgets.add(_replyQuote(context, message, reply));

    if (transfer.phase == FileTransferPhase.downloading) {
      final percent = (transfer.progress.clamp(0.0, 1.0) * 100).round();
      widgets.add(_fileFeedbackText(context, '下载中 $percent%'));
    } else if (transfer.phase == FileTransferPhase.failed) {
      widgets.add(_fileFeedbackText(context, '下载失败，点击重试'));
    }
    if (widgets.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _fileFeedbackText(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.metadata.copyWith(color: context.tokens.danger),
    ),
  );

  /// 标准富消息使用 Flyer 类型参与列表 diff、分页和滚动，但具体视觉与交互
  /// 继续复用项目已验证的气泡，避免媒体迁移改变现有 UI。
  Widget _buildRichMessage(
    String uiMessageId, {
    BubbleGroupPosition groupPosition = BubbleGroupPosition.single,
  }) {
    return Obx(() {
      final domain = flyerController.domainMessage(uiMessageId);
      if (domain == null) return const SizedBox.shrink();
      // 建立文件下载进度的响应依赖。
      controller.fileTransferStates[domain.id];
      final uploadStates = <AttachmentUploadProgressState?>[
        for (var index = 0; index < domain.attachments.length; index++)
          controller.attachmentUploadState(domain, index),
      ];
      final cachedImageBytes = <Uint8List?>[
        if (domain.type == MessageType.image)
          for (var index = 0; index < domain.attachments.length; index++)
            controller.cachedImageBytes(domain, index),
      ];
      return MessageBubble(
        message: domain,
        embeddedInChatLayout: true,
        messageTextSize: settingsController.textSize.value,
        groupPosition: groupPosition,
        onReplyTap: _locateReply,
        onRetryTap: domain.isMine && domain.status == MessageStatus.failed
            ? () => controller.retryMessage(domain)
            : null,
        onMediaTap: (index) => controller.handleMediaTap(domain, index),
        cachedImageBytes: cachedImageBytes,
        onImageDisplayed: (index) =>
            controller.cacheDisplayedImage(domain, index),
        attachmentUploadStates: uploadStates,
        onAttachmentUploadToggle: (index) =>
            controller.toggleAttachmentUpload(domain, index),
        fileTransferState: controller.fileTransferState(domain),
        onFileTap: () => controller.downloadOrOpenFile(domain),
      );
    });
  }

  /// 业务消息同样由 Flyer 列表管理，但完整复用项目业务气泡及其点击行为。
  Widget _buildBusinessMessage(
    String uiMessageId, {
    BubbleGroupPosition groupPosition = BubbleGroupPosition.single,
  }) {
    final domain = flyerController.domainMessage(uiMessageId);
    if (domain == null) return const SizedBox.shrink();

    // 消息列表由 flutter_chat_ui 驱动；此处只渲染当前消息快照。
    return MessageBubble(
      message: domain,
      embeddedInChatLayout: true,
      messageTextSize: settingsController.textSize.value,
      groupPosition: groupPosition,
      onReplyTap: _locateReply,
      onRetryTap: domain.isMine && domain.status == MessageStatus.failed
          ? () => controller.retryMessage(domain)
          : null,
    );
  }

  Widget _buildMessageWrapper(
    BuildContext context,
    flyer.Message message,
    int index,
    Animation<double> animation,
    Widget child, {
    bool? isRemoved,
    required bool isSentByMe,
    flyer.MessageGroupStatus? groupStatus,
  }) {
    final domain = flyerController.domainMessage(message.id);
    final isSystemMessage = message is flyer.SystemMessage;
    final isFirstInGroup = groupStatus?.isFirst ?? true;
    final isLastInGroup = groupStatus?.isLast ?? true;
    final usesAvatarColumn =
        settingsController.showAvatar.value && !isSystemMessage;
    final shouldShowAvatar =
        usesAvatarColumn && isLastInGroup && isRemoved != true;
    final isCurrentUser =
        message.authorId == flyerController.currentUserId.value;
    Widget? avatar;
    if (shouldShowAvatar) {
      avatar = Padding(
        padding: EdgeInsets.only(
          left: isCurrentUser ? 8 : 0,
          right: isCurrentUser ? 0 : 8,
        ),
        child: GestureDetector(
          onLongPress: null,
          child: AppAvatar(
            imageUrl: flyerController.avatarUrlForUser(message.authorId),
            name: flyerController.displayNameForUser(message.authorId),
            size: 32,
          ),
        ),
      );
    } else if (usesAvatarColumn) {
      // 同组中间消息保留头像列宽，确保单聊和群聊的气泡均稳定对齐。
      avatar = const SizedBox(width: 40);
    }

    final dateHeader = domain != null && _startsNewDay(index, domain.time)
        ? _dateDivider(context, domain.time)
        : null;

    final messageContent = child;

    final base = flyer_ui.ChatMessage(
      message: message,
      index: index,
      animation: animation,
      isRemoved: isRemoved,
      groupStatus: groupStatus,
      headerWidget: dateHeader,
      leadingWidget: usesAvatarColumn && !isCurrentUser
          ? avatar
          : !usesAvatarColumn
          ? null
          : const SizedBox(width: 40),
      trailingWidget: usesAvatarColumn && isCurrentUser
          ? avatar
          : !usesAvatarColumn
          ? null
          : const SizedBox(width: 40),
      receivedMessageScaleAnimationAlignment: isSystemMessage
          ? Alignment.center
          : Alignment.centerLeft,
      receivedMessageAlignment: isSystemMessage
          ? AlignmentDirectional.center
          : AlignmentDirectional.centerStart,
      horizontalPadding: isSystemMessage ? 0 : AppSizes.paddingLg,
      verticalPadding: AppSizes.bubbleGapDiff,
      // 系统消息没有“同一发送者连续气泡”的视觉分组语义，连续出现时也应
      // 保持普通消息间距，避免多个状态通知挤在一起。
      verticalGroupedPadding: isSystemMessage
          ? AppSizes.bubbleGapDiff
          : AppSizes.bubbleGapSame,
      bottomWidget:
          domain == null ||
              !domain.isMine ||
              domain.status != MessageStatus.failed
          ? null
          : _sendFailureFeedback(context, domain),
      child: messageContent,
    );
    if (domain == null || domain.isSystem) {
      return base;
    }
    return Obx(() {
      final selecting = controller.selectionMode.value;
      final selected = controller.isSelected(domain.id);
      final highlighted = controller.isHighlighted(domain.id);
      final checkbox = ClipRect(
        child: TweenAnimationBuilder<double>(
          duration: AppConstants.animFast,
          curve: Curves.easeInOut,
          tween: Tween(begin: 0, end: selecting ? 1 : 0),
          builder: (_, factor, child) => Align(
            alignment: domain.isMine
                ? Alignment.centerRight
                : Alignment.centerLeft,
            widthFactor: factor,
            child: child,
          ),
          child: _selectionCheckbox(context, selected, domain.isMine),
        ),
      );
      final row = Row(
        children: domain.isMine
            ? [Expanded(child: base), checkbox]
            : [checkbox, Expanded(child: base)],
      );
      return ClipRect(
        clipper: const _MessageVerticalClipper(horizontalOverflow: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selecting ? () => controller.toggleSelect(domain.id) : null,
          child: AnimatedContainer(
            duration: AppConstants.animFast,
            color: selected || highlighted
                ? context.tokens.itemActive
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: selecting ? AbsorbPointer(child: row) : row,
          ),
        ),
      );
    });
  }

  /// 发送失败反馈属于整条消息状态，不参与气泡内容、时间或回执布局。
  ///
  /// 群聊右侧预留 40px 与发送方头像列对齐；单聊没有头像列，不应残留空白。
  /// 错误图标、完整原因与重试图标共同提供明确反馈。
  Widget _sendFailureFeedback(BuildContext context, MessageModel message) {
    final reason = message.sendError?.trim();
    final text = reason == null || reason.isEmpty ? '发送失败，请重试' : reason;
    return Padding(
      padding: EdgeInsets.only(
        top: AppSizes.paddingXs,
        right: 0,
      ),
      child: Semantics(
        button: true,
        label: '发送失败：$text，点击重试',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
            onTap: () => unawaited(controller.retryMessage(message)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: context.screenSize.width * 0.66,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 15,
                      color: context.tokens.danger,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.badgeLabel.copyWith(
                          color: context.tokens.danger,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: context.tokens.danger,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 当前消息是否为一个自然日的第一条消息。
  bool _startsNewDay(int index, DateTime currentTime) {
    if (index <= 0) return true;
    final messages = flyerController.messages;
    if (index >= messages.length) return false;
    final previous = flyerController.domainMessage(messages[index - 1].id);
    if (previous == null) return false;
    final current = SystemClock.toDisplay(currentTime);
    final before = SystemClock.toDisplay(previous.time);
    return current.year != before.year ||
        current.month != before.month ||
        current.day != before.day;
  }

  /// 日期与系统提示都采用弱化胶囊，不占据整行实色背景。
  Widget _dateDivider(BuildContext context, DateTime time) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSizes.paddingSm),
    child: Center(
      child: _systemMessagePill(context, DateTimeUtil.dateDivider(time)),
    ),
  );

  Widget _systemMessagePill(
    BuildContext context,
    String text, {
    bool service = false,
  }) => Center(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.isDark && service
            ? const Color(0xFF1F1F1F)
            : Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingItem,
          vertical: AppSizes.paddingXs,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.badgeLabel.copyWith(
            color: context.isDark
                ? const Color(0xFFFFFFFF)
                : Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    ),
  );

  Widget _selectionCheckbox(BuildContext context, bool selected, bool isMine) {
    final selectedColor = context.isDark
        ? const Color(0xFFFFFFFF)
        : context.tokens.brand;
    final unselectedBorder = context.isDark
        ? const Color(0xFFFFFFFF)
        : context.colorScheme.outline;
    final checkColor = context.isDark
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    return SizedBox(
      width: 32,
      child: Padding(
        padding: isMine
            ? const EdgeInsets.only(left: AppSizes.paddingSm)
            : const EdgeInsets.only(right: AppSizes.paddingSm),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? selectedColor : Colors.transparent,
            border: Border.all(
              color: selected ? selectedColor : unselectedBorder,
              width: 2,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 15, color: checkColor)
              : null,
        ),
      ),
    );
  }

  void _onMessageTap(
    BuildContext context,
    flyer.Message message,
    TapUpDetails details,
  ) {
    final domain = flyerController.domainMessage(message.id);
    if (domain == null) return;
    if (controller.selectionMode.value) {
      controller.toggleSelect(domain.id);
    } else if (domain.isMine && domain.status == MessageStatus.failed) {
      unawaited(controller.retryMessage(domain));
    } else if (domain.type == MessageType.image) {
      unawaited(controller.handleMediaTap(domain, 0));
    } else if (domain.type == MessageType.file) {
      unawaited(controller.downloadOrOpenFile(domain));
    }
  }

  void _onMessageLongPress(
    BuildContext context,
    flyer.Message message,
    LongPressStartDetails details,
  ) {
    final domain = flyerController.domainMessage(message.id);
    if (domain == null || domain.isSystem || controller.selectionMode.value) {
      return;
    }
    unawaited(_openContextMenu(context, domain, details.globalPosition));
  }

  Future<void> _openContextMenu(
    BuildContext context,
    MessageModel message,
    Offset position,
  ) async {
    final action = await showMessageContextMenu(
      context: context,
      globalPosition: position,
      canRecall: message.isMine,
    );
    if (action == null) return;
    switch (action) {
      case MessageMenuAction.reply:
        controller.startReply(message);
      case MessageMenuAction.copy:
        controller.copyMessage(message);
      case MessageMenuAction.multiSelect:
        controller.enterSelection(message);
      case MessageMenuAction.delete:
        controller.deleteMessage(message);
      case MessageMenuAction.recall:
        controller.recallMessage(message);
    }
  }

  Widget _replyQuote(
    BuildContext context,
    MessageModel message,
    ReplyQuote quote, {
    bool onMedia = false,
  }) {
    final foreground = onMedia || message.isMine
        ? Colors.white
        : context.colorScheme.onSurface;
    return InkWell(
      onTap: quote.messageId == null
          ? null
          : () => unawaited(_locateReply(quote)),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: onMedia
              ? Colors.transparent
              : foreground.withValues(alpha: 0.10),
          border: Border(
            left: BorderSide(color: context.tokens.brand, width: 3),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              quote.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.badgeLabel.copyWith(
                color: onMedia || message.isMine
                    ? foreground
                    : context.tokens.brand,
              ),
            ),
            Text(
              quote.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.metadata.copyWith(
                color: foreground.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _locateReply(ReplyQuote quote) async {
    final messageId = quote.messageId;
    if (!quote.isAvailable || messageId == null) {
      AppToast.info(quote.isAvailable ? '原消息不存在' : quote.summary);
      return;
    }
    final preparedMessageId = await controller.prepareQuotedMessage(quote);
    if (preparedMessageId == null) return;
    await flyerController.synchronizeNow();
    final uiId = flyerController.uiIdForDomainMessageId(messageId);
    if (uiId != null) {
      await flyerController.scrollToMessage(
        uiId,
        alignment: 0.35,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      unawaited(controller.highlightMessage(messageId));
    }
  }

  Widget _replyPreview(BuildContext context) => Obx(() {
    final replying = controller.replyingTo.value;
    if (replying == null) return const SizedBox.shrink();
    return ChatReplyPreview(
      message: replying,
      onClose: controller.cancelReply,
    );
  });

  Widget _attachmentFeedback(BuildContext context) {
    final message = controller.attachmentFeedback.value;
    return AnimatedSwitcher(
      duration: AppConstants.animFast,
      child: message == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(message),
              width: double.infinity,
              margin: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingLg,
                vertical: AppSizes.paddingXs,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingMd,
                vertical: AppSizes.paddingSm,
              ),
              decoration: BoxDecoration(
                color: context.tokens.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.tokens.danger),
              ),
            ),
    );
  }

  Widget _inputPanel(
    BuildContext context,
    ChatInputMode mode,
    double panelHeight,
  ) {
    final open = mode == ChatInputMode.emoji;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final contentHeight = (panelHeight - bottomSafe).clamp(0.0, panelHeight);
    final Widget child = switch (mode) {
      ChatInputMode.emoji => ChatEmojiPanel(
        controller: controller,
        height: contentHeight,
      ),
      _ => const SizedBox.shrink(),
    };
    final panelBackground = context.semanticColors.backgroundGrouped;
    final panel = ClipRect(
      child: ColoredBox(
        // Bottom Slot 只在这里绘制一次完整、实色背景。背景覆盖 content +
        // bottom SafeArea，子面板自身保持透明，深色主题不会再出现第二层
        // 半透明色块或底部 SafeArea 透出聊天背景。
        color: panelBackground,
        child: SizedBox(
          height: panelHeight,
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(bottom: open ? bottomSafe : 0),
            // 不使用 AnimatedSwitcher，避免前后两个全尺寸 panel 在切换帧叠绘。
            child: KeyedSubtree(key: ValueKey(mode), child: child),
          ),
        ),
      ),
    );
    return open ? panel : const SizedBox.shrink();
  }
}

/// 消息只允许气泡尾部横向越界，禁止图片异步重排期间绘制到相邻消息的垂直
/// 区域，避免后一条媒体气泡短暂遮住前一条文字消息。
class _MessageVerticalClipper extends CustomClipper<Rect> {
  const _MessageVerticalClipper({required this.horizontalOverflow});

  final double horizontalOverflow;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -horizontalOverflow,
    0,
    size.width + horizontalOverflow,
    size.height,
  );

  @override
  bool shouldReclip(_MessageVerticalClipper oldClipper) =>
      oldClipper.horizontalOverflow != horizontalOverflow;
}

/// 群活动通话悬浮横幅。
///
/// 使用覆盖层而不是插入消息列表，保证横幅出现或结束时不改变反向列表高度，
/// 从而保持用户当前阅读锚点。

class _ChatMessageSkeleton extends StatelessWidget {
  const _ChatMessageSkeleton();

  static const _bubbleWidths = <double>[176, 224, 138, 202, 164, 236, 148];

  @override
  Widget build(BuildContext context) {
    // 背景由聊天消息区统一渲染，骨架仅覆盖消息占位，避免遮住用户选择。
    return AppSkeletonScope(
      child: ListView.builder(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSizes.paddingMd,
          appTopBarInset(context) + AppSizes.paddingLg,
          AppSizes.paddingMd,
          MediaQuery.paddingOf(context).bottom + AppSizes.paddingSm,
        ),
        itemCount: _bubbleWidths.length,
        itemBuilder: (_, index) {
          final isMine = index.isEven;
          final avatar = isMine
              ? const SizedBox(width: 32)
              : const AppSkeletonBlock.circle(size: 32);
          final bubble = AppSkeletonBlock(
            width: _bubbleWidths[index],
            height: index == 1 || index == 5 ? 72 : 44,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.paddingMd),
            child: Row(
              mainAxisAlignment: isMine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: isMine
                  ? [bubble, const SizedBox(width: AppSizes.paddingSm), avatar]
                  : [avatar, const SizedBox(width: AppSizes.paddingSm), bubble],
            ),
          );
        },
      ),
    );
  }
}

/// 聊天页控制器。
///
/// 管理消息列表、输入模式、引用回复、多选批量操作等聊天页交互状态。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';


import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_exception.dart';
import '../../core/time/system_clock.dart';
import '../../data/enums/chat_input_mode.dart';
import '../../data/enums/conversation_type.dart';
import '../../data/enums/message_status.dart';
import '../../data/enums/message_type.dart';
import '../../data/local/session_storage.dart';
import '../../data/local/im_local_database.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/im_api_models.dart';
import '../../data/models/message_model.dart';
import '../../data/models/message_media_merge.dart';
import '../../data/services/im_sync_service.dart';
import '../../data/services/chat_attachment_picker_service.dart';
import '../../data/services/chat_viewport_state_store.dart';
import '../../data/services/im_pending_message_service.dart';
import '../../data/services/im_receipt_service.dart';
import '../../data/services/system_time_service.dart';
import '../../data/services/image_cache_service.dart';
import '../../data/services/file_transfer_service.dart';
import '../../domain/repositories/im_repository.dart';
import '../../domain/repositories/contact_repository.dart';
import '../../routes/app_routes.dart';
import '../media_preview/media_preview_controller.dart';
import '../../shared/utils/app_toast.dart';

/// 聊天详情页状态
///
/// 只负责 UI 状态与 Mock 数据：消息加载、输入区模式切换、文本编辑状态。
/// 不实现真实录音 / 表情选择 / 消息发送（属第二阶段）。
class ChatController extends GetxController
    with WidgetsBindingObserver, PageReadTracking {
  ChatController({
    ImRepository? repository,
    SessionStorage? storage,
    ChatAttachmentPickerService? attachmentPickerService,
    ConversationModel? conversation,
  }) : _repository = repository ?? Get.find<ImRepository>(),
       _storage = storage ?? Get.find<SessionStorage>(),
       _attachmentPickerService =
           attachmentPickerService ?? Get.find<ChatAttachmentPickerService>(),
       _conversation = Rxn<ConversationModel>(
         conversation ??
             (Get.arguments is ConversationModel
                 ? Get.arguments as ConversationModel
                 : null),
       );

  static const _uuid = Uuid();

  final ImRepository _repository;
  final SessionStorage _storage;
  final ChatAttachmentPickerService _attachmentPickerService;
  final ChatViewportStateStore _viewportStateStore =
      Get.find<ChatViewportStateStore>();
  final SystemTimeService _systemConfigService = Get.find<SystemTimeService>();
  final ImLocalDatabase _database = Get.find<ImLocalDatabase>();
  final ImReceiptService _receiptService = Get.find<ImReceiptService>();
  final FileTransferService _fileTransfers = Get.find<FileTransferService>();
  final ImageCacheService _imageCache = Get.find<ImageCacheService>();
  final fileTransferStates = <String, FileTransferViewState>{}.obs;
  final imageCacheBytes = <String, Uint8List>{}.obs;
  final Set<String> _resolvingImageCache = <String>{};
  final attachmentUploadStates = <String, AttachmentUploadProgressState>{}.obs;

  /// 当前会话。
  ///
  /// 正常跳转直接使用 arguments 中的完整快照；Web 刷新后 arguments 会
  /// 丢失，此时根据 URL 的 conversation_id 从 SQLite/服务端恢复。
  final Rxn<ConversationModel> _conversation;

  ConversationModel? get conversation => _conversation.value;

  final textController = TextEditingController();
  final inputFocusNode = FocusNode();

  final inputMode = ChatInputMode.text.obs;
  final isComposing = false.obs;
  final keyboardHeightRevision = 0.obs;
  final _messages = <MessageModel>[].obs;

  /// 多选模式开关
  final selectionMode = false.obs;

  /// 已选中的消息 id 集合
  final selectedIds = <String>{}.obs;

  /// 当前正在回复的消息（回复预览框数据源）
  final replyingTo = Rxn<MessageModel>();

  /// 引用跳转后短暂高亮的原消息 ID。
  final highlightedMessageId = RxnString();

  final isLoading = false.obs;

  /// 首次 SQLite + 服务端消息窗口加载是否已经结束。
  ///
  /// 新聊天页只有在该状态完成后，才允许在锚点不存在时执行确定性回退，避免
  /// SQLite 尚未投影就错误地认定历史消息已被删除。
  final initialLoadCompleted = false.obs;

  /// SQLite/内存消息窗口是否已经完成首轮投影。
  ///
  /// 有本地消息时新聊天页据此立即展示；该状态不等待 HTTP，避免网络延迟
  /// 重新退化成可感知的整页加载。
  final initialLocalLoadCompleted = false.obs;

  final isLoadingMore = false.obs;
  final isDeletingSelected = false.obs;
  final pickingAttachmentType = Rxn<MessageType>();
  final hasMoreMessages = false.obs;
  final errorMessage = ''.obs;
  final attachmentFeedback = RxnString();
  Timer? _attachmentFeedbackTimer;
  late final StreamSubscription<Map<String, dynamic>> _eventSubscription;
  StreamSubscription<PendingMessageStateChange>? _pendingRetrySubscription;
  StreamSubscription<AttachmentUploadProgressState>?
  _attachmentUploadSubscription;

  /// 仅在 SQLite 入队失败时保留于当前页面，点击失败图标会重新尝试本地入队。
  /// 正常发送失败由 SQLite 待发送队列恢复，不依赖该内存回退。
  final Map<String, Future<void> Function()> _localEnqueueRetries = {};
  int _lastLoadedSeq = 0;
  String? _currentUserId;
  String? _nextBeforeSeq;
  int _loadRevision = 0;
  bool _initialLoadStarted = false;
  bool _viewportAtLatest = true;

  String get conversationId => conversation?.id.trim() ?? '';
  final _singlePeerIsFriend = false.obs;

  int get systemConfigRevision => _systemConfigService.revision.value;
  bool get canUploadAttachments => _systemConfigService.canUploadChatAttachment;
  bool get canSendMessage =>
      _systemConfigService.canChatWith(isFriend: _singlePeerIsFriend.value);

  bool _allowSend({bool attachmentFeedback = false}) {
    if (canSendMessage) return true;
    if (attachmentFeedback) showAttachmentFeedback('当前仅允许好友之间私聊');
    return false;
  }

  /// 新聊天列表适配层读取的不可变消息快照。
  ///
  /// 业务写入仍只能通过本控制器和 SQLite 服务完成，避免 UI 组件直接修改
  /// [_messages] 造成待发送队列、回执和实时事件状态不一致。
  List<MessageModel> get messageSnapshot =>
      List<MessageModel>.unmodifiable(_messages);

  /// 消息投影变化流，供 flutter_chat_ui 控制器转换为细粒度列表操作。
  Stream<List<MessageModel>> get messageChanges => _messages.stream;

  /// 当前登录用户 ID；消息首次加载完成前可能为空。
  String? get currentUserId => _currentUserId;

  String get title => conversation?.title ?? '聊天';

  String get subtitle => '在线';

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _restoreKeyboardHeight();
    unawaited(_resolveConversationAndLoad());
    unawaited(_refreshSinglePeerRelationship());
    _eventSubscription = Get.find<ImSyncService>().appliedEvents.listen((
      event,
    ) {
      if (event['conversation_id']?.toString() == conversation?.id) {
        unawaited(_applyConversationEvent(event));
      }
    });
    if (Get.isRegistered<ImPendingMessageService>()) {
      final pendingService = Get.find<ImPendingMessageService>();
      _pendingRetrySubscription = pendingService.stateChanges.listen(
        _applyPendingStateChange,
      );
      _attachmentUploadSubscription = pendingService.uploadProgressChanges
          .listen((state) => attachmentUploadStates[state.key] = state);
    }
    textController.addListener(() {
      isComposing.value = textController.text.trim().isNotEmpty;
    });
  }

  /// 确保聊天页拥有完整会话后再加载消息。
  ///
  /// Web 刷新不会保留 Get.arguments，因此先查账号隔离 SQLite；本地没有
  /// 时按服务端复合游标分页查找。找不到或 URL 缺少 ID 时返回会话列表，
  /// 禁止继续构建一个无法收发消息的空聊天页。
  Future<void> _resolveConversationAndLoad() async {
    final finishPageRead = pageReads.begin('_resolveConversationAndLoad');
    try {
      if (conversation != null) {
        await _loadMessages();
        return;
      }

      final conversationId = Get.parameters['conversation_id']?.trim() ?? '';
      if (conversationId.isEmpty) {
        _finishUnresolvableConversation('聊天地址缺少会话 ID');
        return;
      }

      try {
        final cached = await _repository.getCachedConversations();
        var resolved = _findConversation(cached, conversationId);
        int? beforeUpdateTime;
        String? beforeConversationId;
        var hasMore = resolved == null;
        while (resolved == null && hasMore) {
          final page = await _repository.getConversations(
            beforeUpdateTime: beforeUpdateTime,
            beforeConversationId: beforeConversationId,
          );
          resolved = _findConversation(page.items, conversationId);
          hasMore = page.hasMore;
          beforeUpdateTime = page.nextBeforeUpdateTime;
          beforeConversationId = page.nextBeforeConversationId;
          if (hasMore &&
              (beforeUpdateTime == null ||
                  beforeConversationId == null ||
                  beforeConversationId.isEmpty)) {
            break;
          }
        }
        if (resolved == null) {
          _finishUnresolvableConversation('会话不存在或当前账号无权访问');
          return;
        }
        _conversation.value = resolved;
        unawaited(_refreshSinglePeerRelationship());
        await _loadMessages();
      } on ApiException catch (error) {
        _finishUnresolvableConversation('会话恢复失败：${error.message}');
      } catch (_) {
        _finishUnresolvableConversation('会话恢复失败，请稍后重试');
      }
    } finally {
      finishPageRead();
    }
  }

  /// 单聊输入能力必须同时服从公共配置与实时好友关系。
  Future<void> _refreshSinglePeerRelationship() async {
    final current = conversation;
    final peerId = current?.peerUserId?.trim() ?? '';
    if (current?.type != ConversationType.single || peerId.isEmpty) return;
    try {
      final profile = await Get.find<ContactRepository>().getUserProfile(
        peerId,
      );
      _singlePeerIsFriend.value = !profile.isStranger;
    } catch (_) {
      // 关系未知时按陌生人处理，避免配置关闭时误放行发送。
      _singlePeerIsFriend.value = false;
    }
  }

  ConversationModel? _findConversation(
    Iterable<ConversationModel> conversations,
    String conversationId,
  ) {
    for (final item in conversations) {
      if (item.id == conversationId) return item;
    }
    return null;
  }

  void _finishUnresolvableConversation(String message) {
    initialLocalLoadCompleted.value = true;
    initialLoadCompleted.value = true;
    errorMessage.value = message;
    AppToast.error(message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed) Get.offNamed(AppRoutes.conversations);
    });
  }

  Future<void> _loadMessages({bool preserveLoadedWindow = false, bool showActivity = true}) async {
    final finishPageRead = pageReads.begin('_loadMessages', visible: showActivity);
    try {
      final revision = ++_loadRevision;
      final isInitialLoad = !_initialLoadStarted;
      _initialLoadStarted = true;
      final conversationId = conversation?.id;
      if (conversationId == null || conversationId.isEmpty) {
        _messages.clear();
        initialLocalLoadCompleted.value = true;
        initialLoadCompleted.value = true;
        return;
      }
      if (isInitialLoad) isLoading.value = true;
      errorMessage.value = '';
      try {
        final previousUserId = _currentUserId;
        _currentUserId ??= (await _storage.readUser())?.id;
        final userId = _currentUserId;
        final snapshot = isInitialLoad && userId != null
            ? _viewportStateStore.read(
                userId: userId,
                conversationId: conversationId,
              )
            : null;
        if (snapshot != null) {
          _replaceMessages(snapshot.messages);
          _lastLoadedSeq = snapshot.lastLoadedSeq;
          _nextBeforeSeq = snapshot.nextBeforeSeq;
          hasMoreMessages.value = snapshot.hasMoreMessages;
          if (snapshot.messages.isNotEmpty) {
            initialLocalLoadCompleted.value = true;
          }
        }
        final cached = await _repository.getCachedMessages(
          conversationId: conversationId,
        );
        if (revision != _loadRevision) return;
        if (cached.isNotEmpty) {
          final cachedWithReceipt = await _mergePeerReceipt(cached);
          if (revision != _loadRevision) return;
          _replaceMessages(_mergeMessageWindows(_messages, cachedWithReceipt));
          _updateLastLoadedSeq();
        }
        if (isInitialLoad) initialLocalLoadCompleted.value = true;
        final page = await _repository.getMessages(
          conversationId: conversationId,
        );
        if (revision != _loadRevision) return;
        var messages = page.items;
        messages = await _mergePeerReceipt(messages);
        if (revision != _loadRevision) return;
        // HTTP 历史不包含尚未确认的本地消息，刷新时必须保留 SQLite 的
        // sending/failed 投影；服务端消息按 client_msg_id 与本地项去重。
        final remoteClientIds = messages
            .map((message) => message.clientMsgId)
            .whereType<String>()
            .toSet();
        final pendingLocal = _messages.where(
          (message) =>
              message.seq == null &&
              !remoteClientIds.contains(message.clientMsgId),
        );
        final earliestRemoteSeq = messages
            .map((message) => message.seq)
            .whereType<int>()
            .fold<int?>(
              null,
              (earliest, seq) =>
                  earliest == null || seq < earliest ? seq : earliest,
            );
        // 最新页用于校验和替换它覆盖的消息区间；只保留服务端明确表示仍有
        // 更早分页时的旧窗口。这样既能恢复历史位置，也不会让已删除/清空的
        // 消息因为内存快照合并而重新出现。
        final preservedOlder = page.hasMore && earliestRemoteSeq != null
            ? _messages.where(
                (message) =>
                    message.seq != null && message.seq! < earliestRemoteSeq,
              )
            : const <MessageModel>[];
        _replaceMessages(
          _mergeMessageWindows(preservedOlder, [...messages, ...pendingLocal]),
        );
        // 恢复页或实时刷新已经拥有更早消息的分页边界，最新 30 条接口不能把
        // 该边界重置，否则返回页面后会从头重复分页并造成视口抖动。
        if (snapshot == null && !preserveLoadedWindow) {
          _nextBeforeSeq = page.nextBeforeSeq;
          hasMoreMessages.value = page.hasMore;
        }
        _updateLastLoadedSeq();
        await _reportReadIfVisible();
      } on ApiException catch (error) {
        errorMessage.value = error.message;
        if (_messages.isEmpty) {
          hasMoreMessages.value = false;
        }
        pageReads.reportError('消息同步失败：${error.message}');
      } catch (_) {
        errorMessage.value = '消息加载失败';
        if (_messages.isEmpty) {
          hasMoreMessages.value = false;
        }
        pageReads.reportError(errorMessage.value);
      } finally {
        // 实时事件可能在首屏请求尚未结束时启动更新。只有最后一次请求可以结束
        // 首屏状态，避免旧请求提前隐藏占位或令新请求失败后永久停在占位页。
        if (revision == _loadRevision) {
          isLoading.value = false;
          initialLocalLoadCompleted.value = true;
          initialLoadCompleted.value = true;
        }
      }
    } finally {
      finishPageRead();
    }
  }

  /// 主动同步当前会话的最新消息。
  ///
  /// 重新拉取当前会话窗口，按稳定消息 ID 合并实时事件和 HTTP 响应。
  Future<void> refreshLatestMessages() =>
      _loadMessages(preserveLoadedWindow: true);

  /// 使用服务端 `before_seq` 加载更早消息。
  /// 反向列表的历史插入和视口稳定由 flutter_chat_ui 自身负责。
  Future<void> loadOlderMessages() async {
    final finishPageRead = pageReads.begin('loadOlderMessages');
    try {
      final conversationId = conversation?.id;
      final beforeSeq = _nextBeforeSeq;
      if (conversationId == null ||
          conversationId.isEmpty ||
          beforeSeq == null ||
          beforeSeq.isEmpty ||
          !hasMoreMessages.value ||
          isLoadingMore.value) {
        return;
      }
      final revision = _loadRevision;
      isLoadingMore.value = true;
      try {
        final page = await _repository.getMessages(
          conversationId: conversationId,
          beforeSeq: beforeSeq,
        );
        if (revision != _loadRevision) return;
        final older = await _mergePeerReceipt(page.items);
        if (revision != _loadRevision) return;
        final existingIds = _messages.map((message) => message.id).toSet();
        final uniqueOlder = older
            .where((message) => existingIds.add(message.id))
            .toList();
        if (uniqueOlder.isNotEmpty) {
          _messages.insertAll(0, uniqueOlder);
        }
        _nextBeforeSeq = page.nextBeforeSeq;
        hasMoreMessages.value = page.hasMore;
      } on ApiException catch (error) {
        errorMessage.value = error.message;
        pageReads.reportError('更早消息加载失败：${error.message}');
      } catch (_) {
        errorMessage.value = '更早消息加载失败';
        pageReads.reportError(errorMessage.value);
      } finally {
        isLoadingMore.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  @override
  void onClose() {
    _saveMessageWindow();
    WidgetsBinding.instance.removeObserver(this);
    _keyboardHeightSaveTimer?.cancel();
    _attachmentFeedbackTimer?.cancel();
    _eventSubscription.cancel();
    _pendingRetrySubscription?.cancel();
    _attachmentUploadSubscription?.cancel();
    _localEnqueueRetries.clear();
    if (_hasRecordedKeyboardHeight) {
      _storage.saveChatKeyboardHeight(_lastKeyboardHeight);
    }
    textController.dispose();
    inputFocusNode.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reportReadIfVisible());
    }
  }

  /// 恢复单聊对端的权威已读水位。
  ///
  /// 群聊按已确认方案不展示 read，避免把任意成员的游标解释为全群已读。
  Future<List<MessageModel>> _mergePeerReceipt(
    List<MessageModel> messages,
  ) async {
    final peerUserId = conversation?.peerUserId;
    final conversationId = conversation?.id;
    if (conversationId == null || conversationId.isEmpty) {
      return messages;
    }
    if (peerUserId == null || peerUserId.isEmpty) return messages;
    final receipt = await _database.readConversationReceipt(
      conversationId: conversationId,
      userId: peerUserId,
    );
    if (receipt == null) return messages;
    return _applyReceiptWatermark(messages, lastReadSeq: receipt.lastReadSeq);
  }

  void _applyReceiptEvent(Map<String, dynamic> event) {
    try {
      final receipt = ImReceiptUpdate.fromEvent(event);
      if (receipt.userId != conversation?.peerUserId) return;
      _replaceMessages(
        _applyReceiptWatermark(_messages, lastReadSeq: receipt.lastReadSeq),
      );
    } on FormatException catch (error) {
      errorMessage.value = error.message.toString();
    }
  }

  /// 将已经成功写入 SQLite 的实时/增量事件同步到当前消息窗口。
  ///
  /// 先针对事件目标即时修正内存，再加载最新页校验服务端状态。这样查看较早
  /// 历史时既不会被强制拉到底部，也不会因视口快照保留已经删除或撤回的旧内容。
  Future<void> _applyConversationEvent(Map<String, dynamic> event) async {
    final eventType = event['event_type']?.toString() ?? '';
    if (eventType == 'receipt_updated') {
      _applyReceiptEvent(event);
      return;
    }
    final messageId = event['message_id']?.toString() ?? '';
    if (eventType == 'message_deleted_for_me' && messageId.isNotEmpty) {
      _messages.removeWhere((message) => message.id == messageId);
    } else if (eventType == 'message_recalled' && messageId.isNotEmpty) {
      final conversationId = conversation?.id;
      if (conversationId != null && conversationId.isNotEmpty) {
        final lookup = await _database.findCachedMessage(
          conversationId: conversationId,
          messageId: messageId,
        );
        final recalled = lookup?.message;
        if (recalled != null) _replaceMessage(messageId, recalled);
        _replaceDirectReplySnapshots(messageId);
      }
    } else if (eventType == 'conversation_updated') {
      _applyConversationWatermarkEvent(event);
    }
    // 解散或被移出事件已经完成本地归约，继续请求历史接口只会得到无权限，
    // 并把正确的业务终态错误展示成“消息同步失败”。
    await _loadMessages(preserveLoadedWindow: true, showActivity: false);
  }

  /// 清空或删除会话事件先裁剪当前内存窗口，防止后续最新页合并时旧消息复活。
  void _applyConversationWatermarkEvent(Map<String, dynamic> event) {
    final payload = event['payload'];
    if (payload is! Map) return;
    final rawConversation = payload['conversation'];
    final conversation = rawConversation is Map ? rawConversation : payload;
    final isDeleted =
        conversation['conversation_deleted'] == true ||
        conversation['member_deleted'] == true ||
        conversation['deleted'] == true;
    if (isDeleted) {
      _messages.clear();
      _nextBeforeSeq = null;
      hasMoreMessages.value = false;
      return;
    }
    final clearedBeforeSeq = int.tryParse(
      conversation['cleared_before_seq']?.toString() ?? '',
    );
    if (clearedBeforeSeq == null || clearedBeforeSeq <= 0) return;
    _messages.removeWhere(
      (message) => message.seq != null && message.seq! <= clearedBeforeSeq,
    );
  }

  List<MessageModel> _applyReceiptWatermark(
    Iterable<MessageModel> messages, {
    required int lastReadSeq,
  }) {
    return messages.map((message) {
      return message.copyWith(
        status: resolveMessageReceiptStatus(
          current: message.status,
          isMine: message.isMine,
          seq: message.seq,
          lastReadSeq: lastReadSeq,
        ),
      );
    }).toList();
  }

  Future<void> _reportReadIfVisible() async {
    final conversationId = conversation?.id;
    // GetX 在 Web/深链场景下可能保留查询参数。只比较路由 path，避免
    // `/chat?conversation_id=...` 被误判为聊天页不可见而跳过已读上报。
    final currentRoutePath =
        Uri.tryParse(Get.currentRoute)?.path ?? Get.currentRoute;
    if (conversationId == null ||
        conversationId.isEmpty ||
        _lastLoadedSeq <= 0 ||
        !_viewportAtLatest ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        currentRoutePath != AppRoutes.chat) {
      return;
    }
    try {
      await _receiptService.reportRead(
        conversationId: conversationId,
        seq: _lastLoadedSeq,
      );
    } catch (_) {
      // 已读是页面可见性派生状态，失败不得清空已加载消息。
      // 重新进入聊天页或回到前台时会幂等再次上报。
    }
  }

  /// 由消息列表视口驱动已读水位；停留历史位置时不得读掉新到消息。
  void updateViewportAtLatest(bool atLatest) {
    if (_viewportAtLatest == atLatest) return;
    _viewportAtLatest = atLatest;
    if (atLatest) unawaited(_reportReadIfVisible());
  }

  /// 社区版聊天顶栏打开单聊对象资料。
  void openProfile() {
    final conv = conversation;
    final userId = conv?.peerUserId ?? '';
    if (conv == null || userId.isEmpty) return;
    Get.toNamed(
      AppRoutes.contactDetail,
      arguments: ContactModel(
        id: userId,
        name: conv.title,
        indexKey: '#',
        avatarUrl: conv.avatarUrl,
        statusText: subtitle,
      ),
    );
  }

  // ===== 输入区交互 =====

  static const double _defaultInputPanelHeight = 300;

  double _lastKeyboardHeight = _defaultInputPanelHeight;
  Timer? _keyboardHeightSaveTimer;
  bool _hasRecordedKeyboardHeight = false;
  final keyboardTransitionPending = false.obs;

  /// 从表情面板切换到系统键盘时，保留最后一个自定义面板的内容，
  /// 直到 IME 完全展开后再完成交接。这样不仅高度不会掉到 0，
  /// 视觉上也不会出现一帧空白底槽。
  final keyboardTransitionSourceMode = Rxn<ChatInputMode>();

  /// 附件功能现在使用聊天区左侧的悬浮纵向胶囊，不再占用 Bottom Slot。
  final attachmentMenuVisible = false.obs;

  double get expectedKeyboardHeight => _hasRecordedKeyboardHeight
      ? _normalizePanelHeight(_lastKeyboardHeight)
      : 0;

  /// 记录系统键盘高度，并给表情/多功能面板复用。
  ///
  /// 面板复用键盘高度可以避免键盘、表情、附件三种输入工具切换时出现高度跳变。
  double inputPanelHeight({
    required double keyboardHeight,
    required bool shouldRecordKeyboardHeight,
  }) {
    if (shouldRecordKeyboardHeight && keyboardHeight > 0) {
      final normalized = _normalizePanelHeight(keyboardHeight);
      final shouldPersist = (normalized - _lastKeyboardHeight).abs() >= 1;
      _lastKeyboardHeight = normalized;
      _hasRecordedKeyboardHeight = true;
      if (shouldPersist) _scheduleSaveKeyboardHeight(normalized);
    }
    return _normalizePanelHeight(_lastKeyboardHeight);
  }

  double _normalizePanelHeight(double height) {
    if (height.isNaN || height.isInfinite || height <= 0) {
      return _defaultInputPanelHeight;
    }
    return height;
  }

  Future<void> _restoreKeyboardHeight() async {
    final value = await _storage.readChatKeyboardHeight();
    if (isClosed || value == null || value.isNaN || value.isInfinite) return;
    _lastKeyboardHeight = _normalizePanelHeight(value);
    _hasRecordedKeyboardHeight = true;
    keyboardHeightRevision.value++;
  }

  void _scheduleSaveKeyboardHeight(double value) {
    _keyboardHeightSaveTimer?.cancel();
    _keyboardHeightSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _storage.saveChatKeyboardHeight(value).catchError((_) {
        // 键盘高度持久化失败不影响当前输入体验，继续使用内存缓存。
      });
    });
  }

  /// 切换到文本输入模式
  void switchToText() => inputMode.value = ChatInputMode.text;

  /// 仅收起表情/多功能面板，不主动拉起系统键盘。
  void collapseInputPanel() {
    keyboardTransitionPending.value = false;
    keyboardTransitionSourceMode.value = null;
    attachmentMenuVisible.value = false;
    if (inputMode.value.isPanelOpen) inputMode.value = ChatInputMode.text;
  }

  /// 切换到文本输入模式并拉起系统键盘。
  void showKeyboard() {
    // 只有 Emoji 是占用 Bottom Slot 的自定义面板。附件菜单已经改为悬浮
    // Overlay，不参与键盘高度交接。
    final sourceMode = inputMode.value;
    final needsPlaceholder = sourceMode.isPanelOpen;
    attachmentMenuVisible.value = false;
    keyboardTransitionSourceMode.value = needsPlaceholder ? sourceMode : null;
    keyboardTransitionPending.value = needsPlaceholder;
    if (needsPlaceholder) inputMode.value = ChatInputMode.text;
    _requestSystemKeyboard();
  }

  /// 主动请求系统输入法显示。
  ///
  /// 只调用 [FocusNode.requestFocus] 在少数 Android 输入法/返回键收键盘后的
  /// 场景中可能不会再次触发 IME 展开，因此在下一帧补发 TextInput.show。
  /// 这只影响展示交接，不改变任何消息业务。
  void _requestSystemKeyboard() {
    inputFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || !inputFocusNode.hasFocus) return;
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    });
  }

  /// 在主动关闭系统键盘前抓取当前真实高度。
  ///
  /// 页面 build 通常已经记录过 viewInsets，但这里再同步一次最终值，可以
  /// 避免用户在 IME 展开动画尚未完全稳定时立刻点“+ / Emoji”导致面板
  /// 复用到前一帧高度。
  void _captureCurrentKeyboardHeight() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    if (height <= 0 || height.isNaN || height.isInfinite) return;
    final normalized = _normalizePanelHeight(height);
    final shouldPersist = (normalized - _lastKeyboardHeight).abs() >= 1;
    _lastKeyboardHeight = normalized;
    _hasRecordedKeyboardHeight = true;
    if (shouldPersist) _scheduleSaveKeyboardHeight(normalized);
  }

  /// 系统已经给出真实键盘高度后，才允许面板把等高空间交给键盘。
  void completeKeyboardTransition() {
    if (!keyboardTransitionPending.value) return;
    keyboardTransitionPending.value = false;
    keyboardTransitionSourceMode.value = null;
    inputMode.value = ChatInputMode.text;
  }

  /// 打开/关闭左侧悬浮附件胶囊。
  ///
  /// 这里不再 unfocus，也不改变 Bottom Slot：如果键盘或 Emoji 正在显示，
  /// 它们保持原高度，附件入口只作为悬浮层出现，因此不会引起消息列表位移。
  void toggleMore() {
    if (!_allowSend(attachmentFeedback: true)) return;
    // 兼容热重载前仍停留在旧 more 输入模式的运行态。
    if (inputMode.value == ChatInputMode.more) {
      inputMode.value = ChatInputMode.text;
    }
    attachmentMenuVisible.value = !attachmentMenuVisible.value;
  }

  void expandAttachmentMenu() {
    if (!_allowSend(attachmentFeedback: true)) return;
    attachmentMenuVisible.value = true;
  }

  void collapseAttachmentMenu() {
    attachmentMenuVisible.value = false;
  }

  /// 切换表情面板；再次点击只收起面板。
  void toggleEmoji() {
    if (!_allowSend(attachmentFeedback: true)) return;
    keyboardTransitionPending.value = false;
    keyboardTransitionSourceMode.value = null;
    attachmentMenuVisible.value = false;
    if (inputMode.value == ChatInputMode.emoji) {
      collapseInputPanel();
      return;
    }
    _captureCurrentKeyboardHeight();
    inputFocusNode.unfocus();
    inputMode.value = ChatInputMode.emoji;
  }

  /// 输入框获得焦点时进入系统键盘态。
  void onInputFocus() {
    if (!_allowSend()) return;
    attachmentMenuVisible.value = false;
    if (inputMode.value.isPanelOpen) {
      keyboardTransitionSourceMode.value = inputMode.value;
      keyboardTransitionPending.value = true;
      inputMode.value = ChatInputMode.text;
      _requestSystemKeyboard();
      return;
    }
    keyboardTransitionSourceMode.value = null;
    keyboardTransitionPending.value = false;
    inputMode.value = ChatInputMode.text;
  }

  /// 显示无法绑定具体气泡的附件前置错误，五秒后自动淡出。
  void showAttachmentFeedback(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    _attachmentFeedbackTimer?.cancel();
    attachmentFeedback.value = normalized;
    _attachmentFeedbackTimer = Timer(const Duration(seconds: 5), () {
      if (!isClosed && attachmentFeedback.value == normalized) {
        attachmentFeedback.value = null;
      }
    });
  }

  Future<void> sendText() async {
    if (!_allowSend()) return;
    if (!canSendMessage) {
      AppToast.warning('当前仅允许好友之间私聊');
      return;
    }
    final text = textController.text.trim();
    final conversationId = conversation?.id;
    if (text.isEmpty || conversationId == null || conversationId.isEmpty) {
      errorMessage.value = '会话尚未准备完成，请稍后重试';
      return;
    }

    final clientMsgId = _uuid.v4();
    final reply = replyingTo.value;
    final pending = MessageModel(
      id: clientMsgId,
      type: MessageType.text,
      conversationId: conversation?.id,
      clientMsgId: clientMsgId,
      isMine: true,
      time: SystemClock.nowUtc,
      text: text,
      status: MessageStatus.sending,
      reply: reply == null
          ? null
          : ReplyQuote(
              messageId: reply.id,
              seq: reply.seq,
              senderId: reply.senderId,
              senderName: reply.senderName ?? (reply.isMine ? '我' : title),
              messageType: reply.type,
              summary: _replySummary(reply),
              preview: _replyPreview(reply),
            ),
    );

    // 用户确认发送后先展示本地气泡；任何磁盘或网络等待都不能阻塞即时反馈。
    _messages.add(pending);
    textController.clear();
    isComposing.value = false;
    replyingTo.value = null;

    try {
      final service = Get.find<ImPendingMessageService>();
      Future<void> enqueue() => service.enqueueText(
        message: pending,
        bodyText: text,
        replyMessageId: reply?.id,
      );
      try {
        await enqueue();
      } catch (_) {
        _localEnqueueRetries[clientMsgId] = enqueue;
        _replaceMessage(
          clientMsgId,
          pending.copyWith(status: MessageStatus.failed),
        );
        AppToast.error('本地保存失败，消息未发送');
        return;
      }
      final sent = await service.sendPending(clientMsgId);
      if (sent == null) {
        throw const ApiException(
          code: 'LOCAL_PENDING_MISSING',
          message: '本地待发送记录已丢失',
        );
      }
      _replaceMessage(clientMsgId, sent.copyWith(status: MessageStatus.sent));
    } on PendingMessageConfirmationException catch (error) {
      AppToast.warning(error.message);
    } on ApiException catch (error) {
      errorMessage.value = error.message;
      if (error.code == 'IM_PRIVATE_CHAT_DISABLED') {
        await Future.wait([
          _systemConfigService.refresh(force: true),
          _refreshSinglePeerRelationship(),
        ]);
        collapseInputPanel();
        AppToast.warning('当前仅允许好友之间私聊');
      }
      _replaceMessage(
        clientMsgId,
        pending.copyWith(status: MessageStatus.failed),
      );
      AppToast.error('消息发送失败：${error.message}');
    } catch (_) {
      errorMessage.value = '消息发送失败';
      _replaceMessage(
        clientMsgId,
        pending.copyWith(status: MessageStatus.failed),
      );
      AppToast.error(errorMessage.value);
    }
  }

  /// 将图片或视频整组作为一条消息发送。
  /// 发送系统选择器返回的一组媒体。
  ///
  /// 图片使用原图字节创建本地预览，随后整组原子入队和上传。
  Future<bool> _sendPickedMediaGroup({
    required MessageType type,
    required List<PickedChatAttachment> selected,
  }) async {
    if (!_allowSend(attachmentFeedback: true)) return false;
    final conversationId = conversation?.id;
    if (conversationId == null || conversationId.isEmpty) {
      showAttachmentFeedback('会话尚未准备完成，请稍后重试');
      return false;
    }
    final clientMsgId = _uuid.v4();
    final pending = MessageModel(
      id: clientMsgId,
      type: type,
      conversationId: conversationId,
      clientMsgId: clientMsgId,
      isMine: true,
      time: SystemClock.nowUtc,
      text: type.previewLabel,
      status: MessageStatus.sending,
      attachments: selected
          .map(
            (item) => MessageAttachment(
              resourceId: '',
              fileName: item.filename,
              fileSize: item.size,
              mimeType: item.mimeType,
              localMediaPath: item.localPath,
            ),
          )
          .toList(growable: false),
    );
    _messages.add(pending);
    final service = Get.find<ImPendingMessageService>();
    var visiblePending = pending;

    Future<void> enqueue() async {
      final prepared = await _preparePickedMedia(
        selected,
        onProgress: (ready) {
          final previews = <MessageAttachment>[
            ...ready.map(_pendingMediaPreview),
            ...selected
                .skip(ready.length)
                .map(
                  (item) => MessageAttachment(
                    resourceId: '',
                    fileName: item.filename,
                    fileSize: item.size,
                    mimeType: item.mimeType,
                  ),
                ),
          ];
          visiblePending = pending.copyWith(attachments: previews);
          _replaceMessage(clientMsgId, visiblePending);
        },
      );
      final withPreviews = pending.copyWith(
        attachments: prepared.map(_pendingMediaPreview).toList(growable: false),
      );
      _replaceMessage(clientMsgId, withPreviews);
      visiblePending = withPreviews;
      await service.enqueueMediaGroup(
        message: withPreviews,
        messageType: type.name,
        attachments: prepared,
      );
    }

    try {
      try {
        await enqueue();
      } catch (error) {
        _localEnqueueRetries[clientMsgId] = enqueue;
        final reason = pendingMessageErrorText(
          error,
          fallback: '图片读取或本地保存失败，请重试',
        );
        _replaceMessage(clientMsgId, visiblePending.copyWith(
          status: MessageStatus.failed,
          sendError: reason,
        ));
        return false;
      }
      final sent = await service.sendPending(clientMsgId);
      if (sent == null) {
        throw const ApiException(
          code: 'LOCAL_PENDING_MISSING',
          message: '本地待发送记录已丢失',
        );
      }
      _replaceMessage(
        clientMsgId,
        sent.copyWith(status: MessageStatus.sent, clearSendError: true),
      );
      return true;
    } on PendingAttachmentUploadPausedException {
      return false;
    } on PendingMessageConfirmationException catch (error) {
      errorMessage.value = error.message;
    } on ApiException catch (error) {
      errorMessage.value = error.message;
    } catch (_) {
      errorMessage.value = '${type.previewLabel}发送失败';
    }
    _replaceMessage(clientMsgId, visiblePending.copyWith(
      status: MessageStatus.failed,
      sendError: errorMessage.value,
    ));
    return false;
  }

  Future<List<PendingMediaAttachment>> _preparePickedMedia(
    List<PickedChatAttachment> selected, {
    void Function(List<PendingMediaAttachment> ready)? onProgress,
  }) async {
    final result = <PendingMediaAttachment>[];
    for (final attachment in selected) {
      try {
        final bytes = await attachment.readBytes();
        result.add(
          PendingMediaAttachment(
            file: MessageUploadFile(
              filename: attachment.filename,
              mimeType: attachment.mimeType,
              bytes: bytes,
            ),
            previewBytes: bytes,
          ),
        );
      } catch (_) {
        throw ApiException(
          code: 'LOCAL_MEDIA_PREPARE_FAILED',
          message: '${attachment.filename} 读取失败',
        );
      }
      onProgress?.call(List.unmodifiable(result));
    }
    return result;
  }

  MessageAttachment _pendingMediaPreview(PendingMediaAttachment item) =>
      MessageAttachment(
        resourceId: '',
        fileName: item.file.filename,
        fileSize: item.originalSize,
        mimeType: item.file.mimeType,
        width: item.width,
        height: item.height,
        durationMs: item.durationMs,
        localPreviewBytes: item.previewBytes,
        localMediaPath: item.sourcePath,
        localMediaBytes: item.file.bytes.isEmpty ? null : item.file.bytes,
      );

  /// 多文件选择后，所有有效文件气泡已一次性出现；本方法只按选择顺序串行
  /// 完成本地持久化、上传和消息确认。
  Future<bool> _sendPickedFile(
    MessageModel pending,
    PickedChatAttachment attachment,
  ) async {
    if (!_allowSend(attachmentFeedback: true)) return false;
    final clientMsgId = pending.clientMsgId!;
    final service = Get.find<ImPendingMessageService>();
    Future<void> enqueue() async {
      final bytes = await attachment.readBytes();
      await service.enqueueAttachment(
        message: pending,
        file: MessageUploadFile(
          filename: attachment.filename,
          mimeType: attachment.mimeType,
          bytes: bytes,
        ),
        messageType: MessageType.file.name,
      );
    }

    try {
      try {
        await enqueue();
      } catch (error) {
        _localEnqueueRetries[clientMsgId] = enqueue;
        final reason = pendingMessageErrorText(
          error,
          fallback: '${attachment.filename} 读取、暂存或本地保存失败，请重试',
        );
        _replaceMessage(
          clientMsgId,
          pending.copyWith(status: MessageStatus.failed, sendError: reason),
        );
        return false;
      }
      final sent = await service.sendPending(clientMsgId);
      if (sent == null) {
        throw const ApiException(
          code: 'LOCAL_PENDING_MISSING',
          message: '本地待发送记录已丢失',
        );
      }
      _replaceMessage(
        clientMsgId,
        sent.copyWith(status: MessageStatus.sent, clearSendError: true),
      );
      return true;
    } on PendingAttachmentUploadPausedException {
      return false;
    } on PendingMessageConfirmationException catch (error) {
      errorMessage.value = error.message;
    } on ApiException catch (error) {
      errorMessage.value = error.message;
      if (error.code == 'FILE_UPLOAD_DISABLED') {
        await _systemConfigService.refresh(force: true);
        collapseInputPanel();
        showAttachmentFeedback('附件上传功能已关闭');
      }
    } catch (_) {
      errorMessage.value = '文件发送失败';
    }
    _replaceMessage(
      clientMsgId,
      pending.copyWith(
        status: MessageStatus.failed,
        sendError: errorMessage.value,
      ),
    );
    return false;
  }

  /// 直接打开系统选择器并发送社区版支持的图片或文件。
  ///
  /// 选择、校验、读取和上传都由 Controller 串行协调；Widget 只触发动作并
  /// 根据 [pickingAttachmentType] 展示即时反馈。取消系统窗口不视为错误。
  Future<void> pickAndSendAttachment(MessageType type) async {
    if (!_allowSend(attachmentFeedback: true)) return;
    if (!canSendMessage) {
      AppToast.warning('当前仅允许好友之间私聊');
      return;
    }
    if (!canUploadAttachments) {
      collapseInputPanel();
      showAttachmentFeedback('附件上传功能已关闭');
      return;
    }
    if (pickingAttachmentType.value != null) return;
    if (type != MessageType.image && type != MessageType.file) {
      showAttachmentFeedback('不支持的附件选择类型');
      return;
    }

    pickingAttachmentType.value = type;
    late final List<PickedChatAttachment> selected;
    try {
      selected = switch (type) {
        MessageType.image => await _attachmentPickerService.pickImages(),
        MessageType.file => await _attachmentPickerService.pickFiles(),
        _ => const <PickedChatAttachment>[],
      };
    } catch (_) {
      showAttachmentFeedback('无法打开系统选择器，请检查文件访问权限');
      return;
    } finally {
      // 这里只保护系统选择窗口，选完后立即允许用户继续选择下一批附件。
      // 文件读取、SQLite 持久化和上传均在各自气泡后台继续执行。
      if (pickingAttachmentType.value == type) {
        pickingAttachmentType.value = null;
      }
    }

    try {
      if (selected.isEmpty) return;

      if (type == MessageType.image && selected.length > 9) {
        showAttachmentFeedback('一条消息最多发送 9 个图片');
        return;
      }

      collapseInputPanel();
      if (type == MessageType.image) {
        for (final attachment in selected) {
          final invalidReason = _attachmentInvalidReason(attachment, type);
          if (invalidReason != null) {
            showAttachmentFeedback(invalidReason);
            return;
          }
        }
        await _sendPickedMediaGroup(type: type, selected: selected);
        return;
      }

      final valid = <PickedChatAttachment>[];
      final invalidReasons = <String>[];
      for (final attachment in selected) {
        final invalidReason = _attachmentInvalidReason(attachment, type);
        if (invalidReason != null) {
          invalidReasons.add(invalidReason);
          continue;
        }
        valid.add(attachment);
      }
      if (invalidReasons.isNotEmpty) {
        showAttachmentFeedback(invalidReasons.join('；'));
      }

      // 快速校验完成后一次性显示所有有效文件，随后再按选择顺序处理文件内容。
      final pendingFiles = <(MessageModel, PickedChatAttachment)>[];
      for (final attachment in valid) {
        final clientMsgId = _uuid.v4();
        final pending = MessageModel(
          id: clientMsgId,
          type: MessageType.file,
          conversationId: conversation?.id,
          clientMsgId: clientMsgId,
          isMine: true,
          time: SystemClock.nowUtc,
          text: MessageType.file.previewLabel,
          status: MessageStatus.sending,
          fileName: attachment.filename,
          fileMeta: '${attachment.size} B',
        );
        _messages.add(pending);
        pendingFiles.add((pending, attachment));
      }
      for (final item in pendingFiles) {
        await _sendPickedFile(item.$1, item.$2);
      }
    } catch (_) {
      showAttachmentFeedback('附件处理失败，请重试');
    }
  }

  bool isPickingAttachment(MessageType type) =>
      pickingAttachmentType.value == type;

  void openMediaPreview(MessageModel message, int initialIndex) {
    final attachments = message.attachments.isNotEmpty
        ? message.attachments
        : <MessageAttachment>[
            MessageAttachment(resourceId: '', resourceUrl: message.imageUrl),
          ];
    Get.toNamed(
      AppRoutes.mediaPreview,
      arguments: MediaPreviewArguments(
        attachments: attachments,
        initialIndex: initialIndex,
        itemContexts: [
          for (var index = 0; index < attachments.length; index++)
            MediaPreviewItemContext(
              senderName: message.senderName ?? (message.isMine ? '我' : title),
              senderAvatarUrl: message.senderAvatarUrl,
              createdAt: message.time,
            ),
        ],
        clientMessageId: message.clientMsgId,
      ),
    );
  }

  Future<void> handleMediaTap(MessageModel message, int attachmentIndex) async {
    openMediaPreview(message, attachmentIndex);
  }

  /// 返回已持久化的图片字节；首次构建时异步查找共享缓存。
  Uint8List? cachedImageBytes(MessageModel message, int attachmentIndex) {
    final request = _imageCacheRequest(message, attachmentIndex);
    if (request == null) return null;
    final cached = imageCacheBytes[request.key];
    if (cached == null && _resolvingImageCache.add(request.key)) {
      unawaited(_restoreCachedImage(request));
    }
    return cached;
  }

  Future<void> _restoreCachedImage(ImageCacheRequest request) async {
    try {
      final bytes = await _imageCache.cachedBytes(request);
      if (bytes != null && bytes.isNotEmpty) {
        imageCacheBytes[request.key] = bytes;
      }
    } finally {
      _resolvingImageCache.remove(request.key);
    }
  }

  /// 图片网络首帧显示成功后持久化，不在收到消息时后台预下载。
  Future<void> cacheDisplayedImage(
    MessageModel message,
    int attachmentIndex,
  ) async {
    final request = _imageCacheRequest(message, attachmentIndex);
    if (request == null || imageCacheBytes.containsKey(request.key)) return;
    if (!await _imageCache.cache(request)) return;
    final bytes = await _imageCache.cachedBytes(request);
    if (bytes != null && bytes.isNotEmpty) imageCacheBytes[request.key] = bytes;
  }

  ImageCacheRequest? _imageCacheRequest(
    MessageModel message,
    int attachmentIndex,
  ) {
    if (message.type != MessageType.image ||
        attachmentIndex < 0 ||
        attachmentIndex >= message.attachments.length) {
      return null;
    }
    final ownerId = _currentUserId?.trim();
    final attachment = message.attachments[attachmentIndex];
    final url = attachment.resourceUrl?.trim();
    final totalBytes = attachment.fileSize ?? 0;
    if (ownerId == null ||
        ownerId.isEmpty ||
        url == null ||
        url.isEmpty ||
        totalBytes <= 0) {
      return null;
    }
    final resourceId = attachment.resourceId.trim().isNotEmpty
        ? attachment.resourceId.trim()
        : '${message.id}:$attachmentIndex';
    return ImageCacheRequest(
      ownerId: ownerId,
      resourceId: resourceId,
      url: url,
      totalBytes: totalBytes,
    );
  }

  FileTransferViewState fileTransferState(MessageModel message) =>
      fileTransferStates[message.id] ?? const FileTransferViewState();

  AttachmentUploadProgressState? attachmentUploadState(
    MessageModel message,
    int attachmentIndex,
  ) {
    final clientMessageId = message.clientMsgId?.trim();
    if (clientMessageId == null || clientMessageId.isEmpty) return null;
    final key = '$clientMessageId:$attachmentIndex';
    return attachmentUploadStates[key] ??
        Get.find<ImPendingMessageService>().uploadState(
          clientMessageId,
          attachmentIndex,
        );
  }

  Future<void> toggleAttachmentUpload(
    MessageModel message,
    int attachmentIndex,
  ) async {
    final clientMessageId = message.clientMsgId?.trim();
    if (clientMessageId == null || clientMessageId.isEmpty) return;
    try {
      await Get.find<ImPendingMessageService>().toggleAttachmentUpload(
        clientMessageId,
        attachmentIndex,
      );
    } catch (_) {
      showAttachmentFeedback('上传暂停状态保存失败，请重试');
    }
  }

  Future<void> downloadOrOpenFile(MessageModel message) async {
    final attachment = message.attachments.isEmpty
        ? null
        : message.attachments.first;
    final current = fileTransferState(message);
    if (current.phase == FileTransferPhase.downloading) return;
    if (current.phase == FileTransferPhase.ready && current.localPath != null) {
      try {
        await _fileTransfers.open(current.localPath!);
      } catch (_) {
        AppToast.error('没有可打开该文件的系统应用');
      }
      return;
    }
    final url = attachment?.resourceUrl;
    if (url == null || url.isEmpty) {
      AppToast.error('文件地址无效，无法下载');
      return;
    }
    fileTransferStates[message.id] = const FileTransferViewState(
      phase: FileTransferPhase.downloading,
    );
    try {
      final path = await _fileTransfers.download(
        url: url,
        resourceId: attachment?.resourceId ?? message.id,
        filename: attachment?.fileName ?? message.fileName ?? 'attachment',
        onProgress: (received, total) {
          if (total <= 0) return;
          fileTransferStates[message.id] = FileTransferViewState(
            phase: FileTransferPhase.downloading,
            progress: (received / total).clamp(0, 1),
          );
        },
      );
      if (path == null) {
        fileTransferStates.remove(message.id);
        AppToast.success('已提交浏览器下载');
      } else {
        fileTransferStates[message.id] = FileTransferViewState(
          phase: FileTransferPhase.ready,
          progress: 1,
          localPath: path,
        );
        AppToast.success('文件下载完成，点击可打开');
      }
    } catch (_) {
      fileTransferStates[message.id] = const FileTransferViewState(
        phase: FileTransferPhase.failed,
      );
      AppToast.error('文件下载失败，点击重试');
    }
  }

  String? _attachmentInvalidReason(
    PickedChatAttachment attachment,
    MessageType type,
  ) {
    if (attachment.size < 1) return '${attachment.filename} 是空文件';
    if (attachment.size > _systemConfigService.uploadMaxBytes) {
      return '${attachment.filename} 超过 ${_systemConfigService.uploadMaxMb}MB，无法发送';
    }
    final mimeType = attachment.mimeType;
    if (_systemConfigService.isUploadTypeDenied(
      filename: attachment.filename,
      mimeType: mimeType,
    )) {
      return '${attachment.filename} 的文件类型不允许发送';
    }
    if (type == MessageType.image && !mimeType.startsWith('image/')) {
      return '${attachment.filename} 不是支持的图片';
    }
    return null;
  }

  // ===== 长按菜单动作 =====

  /// 回复某条消息：填充回复预览框
  void startReply(MessageModel message) {
    replyingTo.value = message;
    switchToText();
  }

  void cancelReply() => replyingTo.value = null;

  /// 复制文本到剪贴板
  void copyMessage(MessageModel message) {
    if (message.text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: message.text));
    }
  }

  /// 重试一条失败消息。
  ///
  /// 点击后立即切换为 sending，阻止重复点击；成功时在原位替换
  /// 服务端消息，失败时恢复 failed 并展示明确错误。
  /// SQLite 队列中的文本和附件统一由发送服务恢复；只有本地入队本身失败时
  /// 才使用当前页面保留的入队动作重新尝试持久化。
  Future<void> retryMessage(MessageModel message) async {
    if (!_allowSend(attachmentFeedback: true)) return;
    if (!message.isMine || message.status != MessageStatus.failed) return;
    final clientMsgId = message.clientMsgId ?? message.id;
    final attachmentMessage = _isAttachmentMessage(message.type);
    if (!Get.isRegistered<ImPendingMessageService>()) {
      if (attachmentMessage) {
        _replaceMessage(clientMsgId, message.copyWith(sendError: '重试服务尚未准备完成'));
      } else {
        AppToast.error('重试服务尚未准备完成');
      }
      return;
    }

    _replaceMessage(
      clientMsgId,
      message.copyWith(status: MessageStatus.sending, clearSendError: true),
    );
    try {
      final service = Get.find<ImPendingMessageService>();
      var sent = await service.sendPending(clientMsgId);
      if (sent == null) {
        final enqueue = _localEnqueueRetries[clientMsgId];
        if (enqueue == null) {
          throw const ApiException(
            code: 'MESSAGE_RETRY_DATA_MISSING',
            message: '消息重试数据已失效',
          );
        }
        await enqueue();
        sent = await service.sendPending(clientMsgId);
        if (sent == null) {
          throw const ApiException(
            code: 'LOCAL_PENDING_MISSING',
            message: '本地待发送记录已丢失',
          );
        }
      }

      final completed = sent.copyWith(
        status: MessageStatus.sent,
        clearSendError: true,
      );
      _replaceMessage(clientMsgId, completed);
      _localEnqueueRetries.remove(clientMsgId);
      if (!attachmentMessage) AppToast.success('消息已重新发送');
    } on PendingAttachmentUploadPausedException {
      // 暂停状态由附件进度圈表达，整条消息仍保留在待发送队列中。
      return;
    } on PendingMessageConfirmationException catch (error) {
      if (attachmentMessage) {
        _replaceMessage(
          clientMsgId,
          message.copyWith(
            status: MessageStatus.failed,
            sendError: error.message,
          ),
        );
      } else {
        AppToast.warning(error.message);
      }
    } on ApiException catch (error) {
      _replaceMessage(
        clientMsgId,
        message.copyWith(
          status: MessageStatus.failed,
          sendError: attachmentMessage ? error.message : null,
        ),
      );
      errorMessage.value = error.message;
      // if (!attachmentMessage) AppToast.error('重试失败：${error.message}');
    } catch (_) {
      _replaceMessage(
        clientMsgId,
        message.copyWith(
          status: MessageStatus.failed,
          sendError: attachmentMessage ? '消息重试失败，请重试' : null,
        ),
      );
      errorMessage.value = '消息重试失败';
      if (!attachmentMessage) AppToast.error(errorMessage.value);
    }
  }

  /// 自动补发状态已经先写 SQLite；当前页面只更新对应内存投影。
  void _applyPendingStateChange(PendingMessageStateChange result) {
    final index = _messages.indexWhere(
      (message) =>
          message.clientMsgId == result.clientMessageId ||
          message.id == result.clientMessageId,
    );
    if (index < 0) return;
    final serverMessage = result.message;
    final current = _messages[index];
    final replacement = serverMessage == null
        ? _messages[index].copyWith(
            status: result.status,
            sendError: result.errorMessage,
            clearSendError:
                result.status == MessageStatus.sending ||
                result.status == MessageStatus.sent,
          )
        : serverMessage.copyWith(
            status: result.status,
            sendError: result.errorMessage,
            clearSendError:
                result.status == MessageStatus.sending ||
                result.status == MessageStatus.sent,
          );
    _messages[index] = mergeTransientMediaState(current, replacement);
    if (result.status == MessageStatus.sent) {
      _localEnqueueRetries.remove(result.clientMessageId);
    }
  }

  /// 单条“仅对我删除”；失败时恢复原位置并给出可见反馈。
  Future<void> deleteMessage(MessageModel message) async {
    if (message.status == MessageStatus.sending) {
      AppToast.warning('消息正在发送，请稍后再删除');
      return;
    }
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    _messages.removeAt(index);
    try {
      if (message.seq == null && message.status == MessageStatus.failed) {
        final clientMessageId = message.clientMsgId ?? message.id;
        await _database.discardPendingMessage(clientMessageId);
        _localEnqueueRetries.remove(clientMessageId);
      } else {
        await _repository.deleteMessageForMe(message.id);
        try {
          await _database.deleteCachedMessage(message.id);
        } catch (_) {}
      }
    } on ApiException catch (error) {
      errorMessage.value = error.message;
      _messages.insert(index, message);
      AppToast.error('消息删除失败：${error.message}');
    } catch (_) {
      errorMessage.value = '消息删除失败';
      _messages.insert(index, message);
      AppToast.error(errorMessage.value);
    }
  }

  Future<void> recallMessage(MessageModel message) async {
    try {
      final recalled = await _repository.recallMessage(messageId: message.id);
      _replaceMessage(message.id, recalled);
      _replaceDirectReplySnapshots(message.id);
    } on ApiException catch (error) {
      errorMessage.value = error.message;
      AppToast.error('消息撤回失败：${error.message}');
    } catch (_) {
      errorMessage.value = '消息撤回失败';
      AppToast.error(errorMessage.value);
    }
  }

  void _replaceDirectReplySnapshots(String recalledMessageId) {
    for (var index = 0; index < _messages.length; index++) {
      final current = _messages[index];
      final reply = current.reply;
      if (reply?.messageId == recalledMessageId) {
        _messages[index] = current.copyWith(reply: reply!.recalled());
      }
    }
  }

  // ===== 多选模式 =====

  /// 进入多选并选中触发的那条消息
  void enterSelection(MessageModel first) {
    // Android 通过返回键收起 IME 后，TextField 仍可能持有焦点。上下文菜单
    // 路由关闭时系统会恢复该焦点，若不在业务入口主动释放，点击任意多选项
    // 都可能重新连接输入法并触发输入态。
    inputFocusNode.unfocus();
    collapseInputPanel();
    selectionMode.value = true;
    selectedIds
      ..clear()
      ..add(first.id);
  }

  void exitSelection() {
    selectionMode.value = false;
    selectedIds.clear();
  }

  void toggleSelect(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    // 全部取消后自动退出多选
    if (selectedIds.isEmpty) selectionMode.value = false;
  }

  bool isSelected(String id) => selectedIds.contains(id);

  bool isHighlighted(String messageId) =>
      highlightedMessageId.value == messageId;

  /// 确保引用原消息已经进入当前内存分页窗口。
  ///
  /// 新旧列表共用此数据步骤，但各自使用自己的滚动控制器完成最终定位。
  /// 全程只查询当前会话 SQLite，绝不把单条消息接口作为渲染前置条件。
  Future<String?> prepareQuotedMessage(ReplyQuote quote) async {
    if (!quote.isAvailable || quote.unavailableReason == 'recalled') {
      AppToast.info('原消息已撤回');
      return null;
    }
    final conversationId = conversation?.id;
    final messageId = quote.messageId?.trim() ?? '';
    if (conversationId == null || conversationId.isEmpty || messageId.isEmpty) {
      AppToast.info('原消息不存在');
      return null;
    }

    AppToast.info('正在定位原消息…');
    final lookup = await _database.findCachedMessage(
      conversationId: conversationId,
      messageId: messageId,
    );
    if (lookup == null) {
      AppToast.info('原消息不存在');
      return null;
    }
    if (lookup.visibility != LocalMessageVisibility.visible) {
      AppToast.info('原消息已删除');
      return null;
    }

    // 原消息存在于 SQLite 但尚未进入当前分页时，只从本地向前扩展。
    while (_messages.indexWhere((message) => message.id == messageId) < 0) {
      final seqs = _messages.map((message) => message.seq).whereType<int>();
      final earliestSeq = seqs.isEmpty
          ? null
          : seqs.reduce((value, seq) => seq < value ? seq : value);
      if (earliestSeq == null) break;
      final older = await _repository.getCachedMessages(
        conversationId: conversationId,
        limit: 100,
        beforeSeq: earliestSeq.toString(),
      );
      if (older.isEmpty) break;
      final existingIds = _messages.map((message) => message.id).toSet();
      final unique = older
          .where((message) => existingIds.add(message.id))
          .toList();
      if (unique.isEmpty) break;
      _messages.insertAll(0, unique);
    }

    final messageIndex = _messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) {
      AppToast.info('原消息不存在');
      return null;
    }
    return messageId;
  }

  /// 引用定位后短暂高亮目标气泡。
  Future<void> highlightMessage(String messageId) async {
    highlightedMessageId.value = messageId;
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (highlightedMessageId.value == messageId) {
      highlightedMessageId.value = null;
    }
  }

  int get selectedCount => selectedIds.length;

  /// 串行执行批量“仅对我删除”。
  ///
  /// 后端当前只有单条删除接口，因此逐条调用以便准确保留失败项；未发成功的
  /// 本地消息没有服务端 message_id，只需先移除待发送队列，避免稍后自动补发。
  Future<void> deleteSelected() async {
    if (isDeletingSelected.value || selectedIds.isEmpty) return;
    final targetIds = Set<String>.of(selectedIds);
    final targets = _messages
        .where((message) => targetIds.contains(message.id))
        .toList();
    if (targets.isEmpty) {
      exitSelection();
      return;
    }

    isDeletingSelected.value = true;
    final deletedIds = <String>{};
    var failedCount = 0;
    var sendingCount = 0;
    try {
      for (final message in targets) {
        // HTTP 请求已经发出但尚未返回 message_id 时无法可靠取消；直接移除
        // 气泡会导致服务端稍后创建成功后消息重新出现，因此明确跳过。
        if (message.status == MessageStatus.sending) {
          sendingCount++;
          continue;
        }
        try {
          final isLocalPending =
              message.seq == null && message.status == MessageStatus.failed;
          if (isLocalPending) {
            final clientMessageId = message.clientMsgId ?? message.id;
            await _database.discardPendingMessage(clientMessageId);
            _localEnqueueRetries.remove(clientMessageId);
          } else {
            await _repository.deleteMessageForMe(message.id);
            // 服务端已经删除成功时，本地缓存清理失败不能把消息重新显示为
            // “未删除”；后续同步事件仍会再次幂等清理 SQLite。
            try {
              await _database.deleteCachedMessage(message.id);
            } catch (_) {}
          }
          deletedIds.add(message.id);
        } catch (_) {
          failedCount++;
        }
      }

      if (deletedIds.isNotEmpty) {
        _messages.removeWhere((message) => deletedIds.contains(message.id));
        selectedIds.removeAll(deletedIds);
      }
      if (selectedIds.isEmpty) exitSelection();

      if (failedCount == 0 && sendingCount == 0) {
        AppToast.success('已删除 ${deletedIds.length} 条消息');
      } else if (deletedIds.isEmpty && sendingCount > 0 && failedCount == 0) {
        AppToast.warning('发送中的消息暂不能删除，请稍后重试');
      } else if (deletedIds.isEmpty) {
        AppToast.error(
          sendingCount == 0
              ? '$failedCount 条消息删除失败，请检查网络后重试'
              : '$failedCount 条删除失败，$sendingCount 条正在发送',
        );
      } else {
        final details = <String>[
          if (failedCount > 0) '$failedCount 条删除失败',
          if (sendingCount > 0) '$sendingCount 条正在发送',
        ];
        AppToast.warning('已删除 ${deletedIds.length} 条，${details.join('，')}');
      }
    } finally {
      isDeletingSelected.value = false;
    }
  }

  void _replaceMessage(String id, MessageModel replacement) {
    final index = _messages.indexWhere(
      (message) =>
          message.id == id ||
          message.clientMsgId == id ||
          (replacement.clientMsgId?.isNotEmpty == true &&
              message.clientMsgId == replacement.clientMsgId),
    );
    if (index >= 0) {
      _messages[index] = mergeTransientMediaState(
        _messages[index],
        replacement,
      );
    }
  }

  bool _isAttachmentMessage(MessageType type) => const {
    MessageType.image,
    MessageType.file,
  }.contains(type);

  String _replySummary(MessageModel message) => switch (message.type) {
    MessageType.text => message.text,
    MessageType.image => '[图片]',
    MessageType.file =>
      message.fileName?.trim().isNotEmpty == true ? message.fileName! : '[文件]',
    _ => message.text.isEmpty ? '[消息]' : message.text,
  };

  ReplyPreview? _replyPreview(MessageModel message) => switch (message.type) {
    MessageType.image => ReplyPreview(
      kind: message.type,
      previewUrl: message.imageUrl,
    ),
    MessageType.file => ReplyPreview(
      kind: MessageType.file,
      fileName: message.fileName,
    ),
    _ => null,
  };

  /// 将离开页面时的消息窗口保存到当前账号的内存缓存。
  /// 新聊天页每次进入固定展示最新消息，不再保存像素滚动位置。
  void _saveMessageWindow() {
    final userId = _currentUserId;
    final conversationId = conversation?.id;
    if (userId == null ||
        userId.isEmpty ||
        conversationId == null ||
        conversationId.isEmpty) {
      return;
    }
    _viewportStateStore.save(
      userId: userId,
      conversationId: conversationId,
      snapshot: ChatViewportSnapshot(
        messages: List<MessageModel>.unmodifiable(_messages),
        lastLoadedSeq: _lastLoadedSeq,
        nextBeforeSeq: _nextBeforeSeq,
        hasMoreMessages: hasMoreMessages.value,
      ),
    );
  }

  /// 合并内存消息窗口与最新缓存/服务端窗口。
  ///
  /// 已确认消息优先使用最新对象以更新回执、撤回等状态；通过
  /// client_msg_id 将本地 sending 气泡与服务端确认消息归并为同一条。
  List<MessageModel> _mergeMessageWindows(
    Iterable<MessageModel> current,
    Iterable<MessageModel> incoming,
  ) {
    final result = current.toList();
    for (final next in incoming) {
      final index = result.indexWhere((item) {
        final sameId = item.id == next.id;
        final currentClientId = item.clientMsgId;
        final nextClientId = next.clientMsgId;
        return sameId ||
            (currentClientId != null &&
                currentClientId.isNotEmpty &&
                currentClientId == nextClientId);
      });
      if (index >= 0) {
        result[index] = next;
      } else {
        result.add(next);
      }
    }
    // 定向系统消息由可靠事件在本地生成，没有 seq。不能把“无 seq”等同于
    // “待发送并永远置底”，否则普通消息确认获得 seq 后会跳到系统消息上方。
    // 所有消息先按发生时间排列；同一时刻的服务端消息再按 seq 排列。
    final indexed = result.asMap().entries.toList(growable: false);
    indexed.sort((leftEntry, rightEntry) {
      final left = leftEntry.value;
      final right = rightEntry.value;
      final timeOrder = left.time.compareTo(right.time);
      if (timeOrder != 0) return timeOrder;

      final leftSeq = left.seq;
      final rightSeq = right.seq;
      if (leftSeq != null && rightSeq != null) {
        final seqOrder = leftSeq.compareTo(rightSeq);
        if (seqOrder != 0) return seqOrder;
      }
      // Dart 的 List.sort 不保证稳定；时间完全相同时保留合并前的位置，
      // 避免发送确认或重复事件导致气泡无意义跳动。
      return leftEntry.key.compareTo(rightEntry.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  void _replaceMessages(Iterable<MessageModel> messages) {
    final currentById = <String, MessageModel>{};
    for (final message in _messages) {
      currentById['id:${message.id}'] = message;
      final clientMessageId = message.clientMsgId?.trim();
      if (clientMessageId != null && clientMessageId.isNotEmpty) {
        currentById['client:$clientMessageId'] = message;
      }
    }
    _messages.value = messages.map((incoming) {
      final clientMessageId = incoming.clientMsgId?.trim();
      final current = clientMessageId != null && clientMessageId.isNotEmpty
          ? currentById['client:$clientMessageId']
          : currentById['id:${incoming.id}'];
      return current == null
          ? incoming
          : mergeTransientMediaState(current, incoming);
    }).toList();
  }

  void _updateLastLoadedSeq() {
    _lastLoadedSeq = _messages
        .map((message) => message.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
  }
}

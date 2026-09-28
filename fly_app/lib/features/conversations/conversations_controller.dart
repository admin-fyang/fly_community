/// 会话列表控制器。
///
/// 提供会话数据、顶栏普通/搜索模式切换与关键字过滤。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import '../../core/utils/social_search.dart';

import 'dart:async';

import '../../core/network/network_recovery_controller.dart';

import 'package:get/get.dart';
import 'package:flutter/widgets.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_sizes.dart';
import '../../data/enums/conversation_type.dart';
import '../../data/enums/message_type.dart';
import '../../data/enums/top_bar_mode.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/conversation_projection_change.dart';
import '../../data/services/system_time_service.dart';
import '../../domain/repositories/im_repository.dart';
import '../../routes/app_routes.dart';
import '../../data/services/im_sync_service.dart';
import '../../shared/utils/app_toast.dart';

/// 会话列表页状态
///
/// 只负责 UI 状态与 Mock 数据：顶栏搜索切换、关键词过滤、列表加载。
/// 不含网络/数据库/真实业务逻辑。
class ConversationsController extends GetxController with PageReadTracking {
  ConversationsController({ImRepository? repository})
      : _repository = repository ?? Get.find<ImRepository>();

  final ImRepository _repository;

  /// 首页名称
  final SystemTimeService systemConfig = Get.find<SystemTimeService>();
  String get homeTitle {
    systemConfig.revision.value;

    String title = systemConfig.appName ?? '消息';
    return title;
  }

  /// 顶栏模式：普通 ↔ 搜索
  final topBarMode = TopBarMode.normal.obs;

  /// 搜索关键词
  final keyword = ''.obs;

  /// 全部会话（已排序：置顶优先，再按时间倒序）
  final _all = <ConversationModel>[].obs;
  final scrollController = ScrollController();
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = false.obs;
  final errorMessage = ''.obs;
  final isSelectionMode = false.obs;
  final selectedIds = <String>{}.obs;
  final isBatchOperating = false.obs;
  final batchAction = ''.obs;
  late final StreamSubscription<ConversationProjectionChange>
      _projectionSubscription;
  int? _nextBeforeUpdateTime;
  String? _nextBeforeConversationId;
  int _loadRevision = 0;
  int _projectionRevision = 0;

  int get selectedCount => selectedIds.length;

  bool get allSelectedMuted {
    if (selectedIds.isEmpty) return false;
    return selectedIds.every(
      (id) => _all.any(
        (conversation) => conversation.id == id && conversation.isMuted,
      ),
    );
  }

  bool get allSelectedPinned {
    if (selectedIds.isEmpty) return false;
    return selectedIds.every(
      (id) => _all.any(
        (conversation) => conversation.id == id && conversation.isPinned,
      ),
    );
  }

  StreamSubscription<void>? _networkRecoverySubscription;

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<NetworkRecoveryController>()) {
      _networkRecoverySubscription = Get.find<NetworkRecoveryController>()
          .recovered
          .listen((_) {
            if (!isClosed && errorMessage.value.isNotEmpty) unawaited(_load(showActivity: false));
          });
    }
    scrollController.addListener(_onScroll);
    // 必须先订阅再加载缓存，避免页面初始化期间恰好提交的新消息丢失通知。
    _projectionSubscription = _repository.watchConversationChanges().listen(
      _applyProjectionChange,
    );
    unawaited(_load());
  }

  /// 直接消费事务提交后的完整会话投影，不再根据事件类型二次猜测或查库。
  void _applyProjectionChange(ConversationProjectionChange change) {
    if (isClosed) return;
    _projectionRevision++;
    if (change.isDeleted) {
      _all.removeWhere((item) => item.id == change.conversationId);
      selectedIds.remove(change.conversationId);
      if (selectedIds.isEmpty && !isBatchOperating.value) {
        isSelectionMode.value = false;
      }
      return;
    }
    final conversation = change.conversation;
    if (conversation == null) return;
    errorMessage.value = '';
    isLoading.value = false;
    final index = _all.indexWhere((item) => item.id == conversation.id);
    if (index < 0) {
      _all.add(conversation);
    } else {
      _all[index] = conversation;
    }
    _sortConversations();
  }

  @override
  void onClose() {
    _networkRecoverySubscription?.cancel();
    _projectionSubscription.cancel();
    scrollController.dispose();
    super.onClose();
  }

  Future<void> _load({bool showActivity = true}) async {
    final finishPageRead = pageReads.begin('_load', visible: showActivity);
    try {
      final revision = ++_loadRevision;
      final stopwatch = Stopwatch()..start();
      debugPrint('[IM conversations][$revision] 首屏加载开始');
      isLoading.value = _all.isEmpty;
      errorMessage.value = '';
      try {
        debugPrint('[IM conversations][$revision] 开始读取 SQLite 会话缓存');
        final cached = await _repository.getCachedConversations();
        debugPrint(
          '[IM conversations][$revision] SQLite 缓存完成：${cached.length} 条，'
          '${stopwatch.elapsedMilliseconds}ms',
        );
        if (isClosed || revision != _loadRevision) return;
        if (cached.isNotEmpty) {
          _all.assignAll(cached);
          isLoading.value = false;
        }
        debugPrint('[IM conversations][$revision] 开始请求服务端会话列表');
        final projectionRevisionBeforeRequest = _projectionRevision;
        final page = await _repository.getConversations();
        debugPrint(
          '[IM conversations][$revision] 服务端会话完成：${page.items.length} 条，'
          '${stopwatch.elapsedMilliseconds}ms',
        );
        if (isClosed || revision != _loadRevision) return;
        // HTTP 返回值已经是 Repository 写入 SQLite 后的完整投影，必须作为
        // 首屏可靠数据源。广播流可能因 Web 首次建库时序未被页面消费，不能
        // 让页面仅依赖瞬时通知；若请求期间已有投影事件，则保留事件更新过的
        // 同 ID 会话，只补入当前列表缺失的服务端项。
        final hasProjectionUpdates =
            _projectionRevision != projectionRevisionBeforeRequest;
        _mergePageItems(page.items, preserveExisting: hasProjectionUpdates);
        debugPrint('[IM conversations][$revision] 首屏投影合并完成：${_all.length} 条');
        _nextBeforeUpdateTime = page.nextBeforeUpdateTime;
        _nextBeforeConversationId = page.nextBeforeConversationId;
        hasMore.value = page.hasMore;
      } on ApiException catch (error) {
        if (isClosed || revision != _loadRevision) return;
        debugPrint(
          '[IM conversations][$revision] API 加载失败：${error.code} ${error.message}',
        );
        errorMessage.value = error.message;
        if (_all.isEmpty) hasMore.value = false;
      } catch (error, stackTrace) {
        if (isClosed || revision != _loadRevision) return;
        debugPrint('[IM conversations][$revision] 加载异常：$error');
        debugPrintStack(
          label: '[IM conversations][$revision] stack',
          stackTrace: stackTrace,
        );
        errorMessage.value = '会话加载失败';
        if (_all.isEmpty) hasMore.value = false;
      } finally {
        if (!isClosed && revision == _loadRevision) isLoading.value = false;
        stopwatch.stop();
        debugPrint(
          '[IM conversations][$revision] 首屏加载结束：'
          '${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } finally {
      finishPageRead();
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients ||
        scrollController.position.pixels <
            scrollController.position.maxScrollExtent - 120) {
      return;
    }
    unawaited(loadMore());
  }

  Future<void> loadMore() async {
    final finishPageRead = pageReads.begin('loadMore');
    try {
      final beforeUpdateTime = _nextBeforeUpdateTime;
      final beforeConversationId = _nextBeforeConversationId;
      if (!hasMore.value ||
          isLoadingMore.value ||
          beforeUpdateTime == null ||
          beforeConversationId == null ||
          beforeConversationId.isEmpty) {
        return;
      }
      final revision = _loadRevision;
      isLoadingMore.value = true;
      try {
        final page = await _repository.getConversations(
          beforeUpdateTime: beforeUpdateTime,
          beforeConversationId: beforeConversationId,
        );
        if (isClosed || revision != _loadRevision) return;
        // 分页同样显式补入返回投影，避免广播通知遗漏导致页面无法继续增长。
        _mergePageItems(page.items, preserveExisting: true);
        _nextBeforeUpdateTime = page.nextBeforeUpdateTime;
        _nextBeforeConversationId = page.nextBeforeConversationId;
        hasMore.value = page.hasMore;
      } on ApiException catch (error) {
        if (isClosed || revision != _loadRevision) return;
        errorMessage.value = error.message;
      } catch (_) {
        if (isClosed || revision != _loadRevision) return;
        errorMessage.value = '更多会话加载失败';
      } finally {
        if (!isClosed && revision == _loadRevision) isLoadingMore.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  /// 过滤后的列表：关键词匹配标题或预览
  List<ConversationModel> get conversations {
    final ordinary = _all;
    final kw = keyword.value.trim();
    if (kw.isEmpty) return ordinary;
    return ordinary.where((c) {
      return SocialSearch.matches(
            kw,
            c.searchName ?? c.title,
            identifier: c.searchIdentifier,
            type: 'user',
          ) ||
          c.lastMessageText.toLowerCase().contains(kw.toLowerCase());
    }).toList();
  }

  /// 打开搜索模式
  void openSearch() => topBarMode.value = TopBarMode.search;

  /// 关闭搜索并清空关键词
  void closeSearch() {
    keyword.value = '';
    topBarMode.value = TopBarMode.normal;
  }

  /// 更新搜索关键词
  void updateKeyword(String value) => keyword.value = value;

  /// 长按进入多选，并选中触发项。
  void enterSelection(ConversationModel conversation) {
    if (isBatchOperating.value) return;
    isSelectionMode.value = true;
    _select(conversation.id);
  }

  void toggleSelection(ConversationModel conversation) {
    if (isBatchOperating.value) return;
    if (selectedIds.contains(conversation.id)) {
      selectedIds.remove(conversation.id);
    } else {
      _select(conversation.id);
    }
  }

  /// 批量接口最多接受 100 个 ID，在选择阶段即时阻止超限并给出明确反馈。
  void _select(String conversationId) {
    if (selectedIds.length >= 100) {
      AppToast.warning('一次最多选择 100 个会话');
      return;
    }
    selectedIds.add(conversationId);
  }

  void exitSelection() {
    if (isBatchOperating.value) return;
    selectedIds.clear();
    isSelectionMode.value = false;
  }

  /// 所选项全部静音时执行取消静音，否则统一静音。
  /// 成功项退出选择，失败项保留，便于用户直接重试。
  Future<void> toggleSelectedMuted() async {
    if (selectedIds.isEmpty || isBatchOperating.value) return;
    final ids = selectedIds.toList(growable: false);
    final shouldMute = !allSelectedMuted;
    final result = await _runBatch(
      action: 'mute',
      request: () => _repository.updateConversationsMuted(
        conversationIds: ids,
        isMuted: shouldMute,
      ),
    );
    if (result == null) return;
    final succeeded = _successfulRequestedIds(ids, result);
    for (final id in succeeded) {
      final index = _all.indexWhere((item) => item.id == id);
      if (index >= 0) {
        _all[index] = _all[index].copyWith(isMuted: shouldMute);
      }
    }
    _completeBatch(
      requestedIds: ids,
      succeededIds: succeeded,
      successMessage: shouldMute ? '已静音' : '已取消静音',
    );
  }

  /// 清空所选会话的服务端历史可见水位，并同步移除内存中的旧消息预览。
  Future<void> clearSelected() async {
    if (selectedIds.isEmpty || isBatchOperating.value) return;
    final ids = selectedIds.toList(growable: false);
    final result = await _runBatch(
      action: 'clear',
      request: () => _repository.clearConversations(ids),
    );
    if (result == null) return;
    final succeeded = _successfulRequestedIds(ids, result);
    for (final id in succeeded) {
      final index = _all.indexWhere((item) => item.id == id);
      if (index >= 0) _all[index] = _all[index].clearMessagePreview();
    }
    _completeBatch(
      requestedIds: ids,
      succeededIds: succeeded,
      successMessage: '已清空',
    );
  }

  /// 所选项全部置顶时取消置顶，否则统一置顶，并立即重排会话列表。
  Future<void> toggleSelectedPinned() async {
    if (selectedIds.isEmpty || isBatchOperating.value) return;
    final ids = selectedIds.toList(growable: false);
    final shouldPin = !allSelectedPinned;
    final result = await _runBatch(
      action: 'pin',
      request: () => _repository.updateConversationsPinned(
        conversationIds: ids,
        isPinned: shouldPin,
      ),
    );
    if (result == null) return;
    final succeeded = _successfulRequestedIds(ids, result);
    for (final id in succeeded) {
      final index = _all.indexWhere((item) => item.id == id);
      if (index >= 0) {
        _all[index] = _all[index].copyWith(isPinned: shouldPin);
      }
    }
    _sortConversations();
    _completeBatch(
      requestedIds: ids,
      succeededIds: succeeded,
      successMessage: shouldPin ? '已置顶' : '已取消置顶',
    );
  }

  /// 批量删除当前用户会话记录；成功项立即移出列表，失败项保持选中。
  Future<void> deleteSelected() async {
    if (selectedIds.isEmpty || isBatchOperating.value) return;
    final ids = selectedIds.toList(growable: false);
    final result = await _runBatch(
      action: 'delete',
      request: () => _repository.deleteConversations(ids),
    );
    if (result == null) return;
    final succeeded = _successfulRequestedIds(ids, result);
    _all.removeWhere((item) => succeeded.contains(item.id));
    _completeBatch(
      requestedIds: ids,
      succeededIds: succeeded,
      successMessage: '已删除',
    );
  }

  /// 统一管理批量 Loading 与网络错误，保证所有按钮在请求期间同步禁用。
  Future<ConversationBatchResult?> _runBatch({
    required String action,
    required Future<ConversationBatchResult> Function() request,
  }) async {
    isBatchOperating.value = true;
    batchAction.value = action;
    try {
      return await request();
    } on ApiException catch (error) {
      AppToast.error('批量操作失败：${error.message}');
      return null;
    } catch (_) {
      AppToast.error('批量操作失败，请稍后重试');
      return null;
    } finally {
      isBatchOperating.value = false;
      batchAction.value = '';
    }
  }

  Set<String> _successfulRequestedIds(
    List<String> requestedIds,
    ConversationBatchResult result,
  ) {
    final requested = requestedIds.toSet();
    return result.successfulIds.where(requested.contains).toSet();
  }

  /// 成功项退出选择，失败项保留；完全成功时自动退出多选并给绿色反馈。
  void _completeBatch({
    required List<String> requestedIds,
    required Set<String> succeededIds,
    required String successMessage,
  }) {
    selectedIds.removeAll(succeededIds);
    final successCount = succeededIds.length;
    final failedCount = requestedIds.length - successCount;
    if (failedCount == 0) {
      isSelectionMode.value = false;
      AppToast.success('$successMessage $successCount 个会话');
    } else {
      AppToast.warning('成功 $successCount 个，失败 $failedCount 个');
    }
  }

  void _sortConversations() {
    _all.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byTime = b.time.compareTo(a.time);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
  }

  /// 将 Repository 已提交 SQLite 的分页投影合入当前列表。
  ///
  /// [preserveExisting] 为 true 时只补缺失项，防止请求期间的实时事件被
  /// 较早的 HTTP 快照覆盖；无投影事件时则允许响应刷新同 ID 的旧缓存。
  void _mergePageItems(
    Iterable<ConversationModel> items, {
    required bool preserveExisting,
  }) {
    for (final item in items) {
      final index = _all.indexWhere((current) => current.id == item.id);
      if (index < 0) {
        _all.add(item);
      } else if (!preserveExisting) {
        _all[index] = item;
      }
    }
    _sortConversations();
  }
}

/// 设备列表及撤销状态；异步结果受页面版本和登录会话双重保护。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../domain/entities/device_session.dart';
import '../../domain/repositories/device_session_repository.dart';

class DeviceManagementController extends GetxController with PageReadTracking {
  DeviceManagementController(this._repository, {required this.readSessionId});

  final DeviceSessionRepository _repository;
  final Future<String?> Function() readSessionId;
  final currentSession = Rxn<DeviceSession>();
  final items = <DeviceSession>[].obs;
  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final errorMessage = ''.obs;
  final operationError = ''.obs;
  final revokingId = RxnString();
  final isRevokingAll = false.obs;
  final revokeAllProgress = ''.obs;
  final revokedCount = 0.obs;
  final hasMore = false.obs;
  final scrollController = ScrollController();

  final Set<String> _revokedIds = {};
  final Set<String> _loadedCursors = {};
  String? _ownerSessionId;
  String? _nextCursor;
  int _revision = 0;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    unawaited(refreshSessions());
  }

  Future<bool> _isCurrent(int revision, String? owner) async =>
      !_closed &&
      revision == _revision &&
      owner != null &&
      await readSessionId() == owner &&
      !_closed &&
      revision == _revision;

  /// 刷新保留旧列表。页内墓碑防止撤销之前发出的请求重新插入目标记录。
  Future<void> refreshSessions() => _load(reset: true);

  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    final finishPageRead = pageReads.begin('_load');
    try {
      if (_closed ||
          isRevokingAll.value ||
          (!reset &&
              (isLoading.value || isLoadingMore.value || !hasMore.value))) {
        return;
      }
      final revision = reset ? ++_revision : _revision;
      final cursor = reset ? null : _nextCursor;
      if (reset) {
        isLoading.value = true;
        isLoadingMore.value = false;
      } else {
        isLoadingMore.value = true;
      }
      errorMessage.value = '';
      final owner = await readSessionId();
      if (_closed || revision != _revision) return;
      if (_ownerSessionId != null && _ownerSessionId != owner) {
        currentSession.value = null;
        items.clear();
        _revokedIds.clear();
      }
      _ownerSessionId = owner;
      try {
        if (owner == null) {
          throw const ApiException(
            code: 'NO_SESSION',
            message: '登录状态已失效，请重新登录',
          );
        }
        final result = await _repository.getSessions(cursor: cursor);
        if (!await _isCurrent(revision, owner)) return;
        if (result.currentSession.sessionId != owner) {
          throw const FormatException('当前登录会话不匹配，请重新进入设备管理');
        }
        if (!reset &&
            result.nextCursor != null &&
            (result.nextCursor == cursor ||
                _loadedCursors.contains(result.nextCursor))) {
          throw const FormatException('设备列表分页异常，请刷新后重试');
        }
        if (reset) _loadedCursors.clear();
        if (cursor != null) _loadedCursors.add(cursor);
        final merged = <String, DeviceSession>{
          if (!reset)
            for (final item in items) item.sessionId: item,
          for (final item in result.items)
            if (item.sessionId != owner &&
                !_revokedIds.contains(item.sessionId))
              item.sessionId: item,
        }.values.toList();
        merged.sort((a, b) {
          final time = (b.lastActiveAt?.millisecondsSinceEpoch ?? 0).compareTo(
            a.lastActiveAt?.millisecondsSinceEpoch ?? 0,
          );
          return time != 0 ? time : b.sessionId.compareTo(a.sessionId);
        });
        currentSession.value = result.currentSession;
        items.assignAll(merged);
        _nextCursor = result.nextCursor;
        hasMore.value = _nextCursor != null;
      } catch (error) {
        if (!_closed &&
            revision == _revision &&
            await readSessionId() == owner) {
          if (!reset &&
              error is ApiException &&
              error.code == 'AUTH_SESSION_CURSOR_INVALID') {
            // 后端快照游标已失效：丢弃分页位置，仅回源第一页一次。
            // 首屏恢复失败仍保留已有列表，并通过原页内重试入口重新加载。
            _nextCursor = null;
            _loadedCursors.clear();
            hasMore.value = false;
            await refreshSessions();
            return;
          }
          errorMessage.value = switch (error) {
            ApiException e => e.message,
            FormatException e => e.message,
            _ => '设备列表加载失败，请稍后重试',
          };
        }
      } finally {
        if (!_closed && revision == _revision) {
          isLoading.value = false;
          isLoadingMore.value = false;
        }
      }
    } finally {
      finishPageRead();
    }
  }

  /// 在打开确认框前清除上一次操作错误，业务状态不由 Widget 直接修改。
  void prepareRevoke() {
    if (isRevokingAll.value || revokingId.value != null) return;
    operationError.value = '';
    revokeAllProgress.value = '';
    revokedCount.value = 0;
  }

  /// 先分页取得完整快照，再顺序撤销，避免边删边翻页造成漏项。
  /// 遇到失败立即停止；重试重新获取快照，不自动重放结果未知的删除请求。
  Future<bool> revokeAllOthers() async {
    if (_closed || isRevokingAll.value || revokingId.value != null) {
      return false;
    }
    isRevokingAll.value = true;
    operationError.value = '';
    revokedCount.value = 0;
    revokeAllProgress.value = '正在获取全部其他会话…';
    // 使进入批量操作前的刷新/分页响应失效，操作期间不启动新的列表请求。
    final revision = ++_revision;
    isLoading.value = false;
    isLoadingMore.value = false;
    final owner = _ownerSessionId;
    var total = 0;
    var deleting = false;
    try {
      if (owner == null || !await _isCurrent(revision, owner)) {
        throw const FormatException('登录状态已变化，请重新进入设备管理');
      }
      final targets = <String, DeviceSession>{};
      final cursors = <String>{};
      String? cursor;
      do {
        if (!await _isCurrent(revision, owner)) return false;
        final page = await _repository.getSessions(cursor: cursor);
        if (!await _isCurrent(revision, owner)) return false;
        if (page.currentSession.sessionId != owner) {
          throw const FormatException('当前登录会话不匹配，请重新进入设备管理');
        }
        for (final item in page.items) {
          if (item.sessionId != owner &&
              !_revokedIds.contains(item.sessionId)) {
            targets[item.sessionId] = item;
          }
        }
        cursor = page.nextCursor;
        if (cursor != null && !cursors.add(cursor)) {
          throw const FormatException('设备列表分页异常，请刷新后重试');
        }
      } while (cursor != null);

      total = targets.length;
      deleting = true;
      for (final id in targets.keys) {
        if (!await _isCurrent(revision, owner)) return false;
        revokeAllProgress.value = '正在注销 ${revokedCount.value + 1}/$total 个会话…';
        await _repository.revokeSession(id);
        if (!await _isCurrent(revision, owner)) return false;
        _revokedIds.add(id);
        items.removeWhere((item) => item.sessionId == id);
        revokedCount.value++;
      }
      // 完整快照已处理完毕，清除旧列表中已经在其他终端退出的过期记录。
      items.clear();
      _nextCursor = null;
      _loadedCursors.clear();
      hasMore.value = false;
      errorMessage.value = '';
      revokeAllProgress.value = total == 0 ? '没有需要注销的其他会话' : '已注销 $total 个会话';
      return true;
    } catch (error) {
      if (_closed || !await _isCurrent(revision, owner)) return false;
      final reason = deleting
          ? _revokeError(error)
          : switch (error) {
              ApiException e => e.message,
              FormatException e => e.message,
              _ => '设备列表加载失败，请稍后重试',
            };
      operationError.value = deleting
          ? '已注销 ${revokedCount.value}/$total 个会话，操作已停止。$reason'
          : '未注销任何会话。$reason';
      return false;
    } finally {
      final valid = await _isCurrent(revision, owner);
      if (!_closed) {
        if (!valid) {
          revokeAllProgress.value = '';
          operationError.value = '登录状态已变化，注销操作已停止';
        }
        isRevokingAll.value = false;
      }
    }
  }

  Future<bool> revoke(DeviceSession session) async {
    if (_closed || isRevokingAll.value || revokingId.value != null) {
      return false;
    }
    operationError.value = '';
    final owner = _ownerSessionId;
    if (owner == null || session.sessionId == owner) {
      operationError.value = '当前登录会话不能在此退出';
      return false;
    }
    revokingId.value = session.sessionId;
    try {
      if (await readSessionId() != owner || _closed) return false;
      await _repository.revokeSession(session.sessionId);
      if (_closed || await readSessionId() != owner) return false;
      _revokedIds.add(session.sessionId);
      items.removeWhere((item) => item.sessionId == session.sessionId);
      return true;
    } catch (error) {
      if (_closed || await readSessionId() != owner) return false;
      operationError.value = _revokeError(error);
      return false;
    } finally {
      if (!_closed) revokingId.value = null;
    }
  }

  /// 单条和批量撤销使用相同错误语义，超时不等同于服务端失败。
  String _revokeError(Object error) => switch (error) {
    ApiException e
        when e.kind == ApiFailureKind.timeout ||
            e.kind == ApiFailureKind.connection ||
            e.code == 'INVALID_RESPONSE' =>
      '结果暂未确认，请取消后刷新设备列表',
    ApiException e => e.message,
    _ => '退出失败，请稍后重试',
  };

  void _onScroll() {
    if (scrollController.hasClients &&
        scrollController.position.extentAfter < 240 &&
        errorMessage.value.isEmpty) {
      unawaited(loadMore());
    }
  }

  @override
  void onClose() {
    _closed = true;
    ++_revision;
    scrollController.dispose();
    super.onClose();
  }
}

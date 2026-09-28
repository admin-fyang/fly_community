library;

import 'dart:async';

import '../../domain/repositories/im_repository.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/log_util.dart';
import '../local/session_storage.dart';
import '../local/im_local_database.dart';
import '../models/im_api_models.dart';
import '../models/message_model.dart';
import 'im_event_reducer.dart';
import 'im_protocol_issue_reporter.dart';
import 'device_service.dart';
import 'directory_sync_service.dart';

/// 发起增量同步的业务原因，用于合并策略与无敏感信息的诊断日志。
enum ImSyncReason {
  manual,
  resume,
  networkRestored,
  realtimeReconnected,
  healthCheck,
  initialSubscription,
  recoveryFailed,
  bootstrapTimeout,
}

/// IM 增量同步服务。
///
/// 负责 REST 增量补偿、实时事件统一归约和权威同步游标持久化。
class ImSyncService {
  ImSyncService(
    this._repository,
    this._deviceService,
    this._storage,
    this._database, [
    this._protocolReporter,
    this._directorySync,
  ]) : _reducer = ImEventReducer(_database);

  final ImRepository _repository;
  final DeviceService _deviceService;
  final SessionStorage _storage;
  final ImLocalDatabase _database;
  final ImProtocolIssueReporter? _protocolReporter;
  final DirectorySyncService? _directorySync;
  final ImEventReducer _reducer;
  final _appliedEvents = StreamController<Map<String, dynamic>>.broadcast();
  Future<ImSyncResult>? _syncTask;
  bool _trailingSyncRequested = false;
  ImSyncReason? _trailingReason;
  bool _realtimeSubscribed = false;
  int _sessionGeneration = 0;

  /// 退出登录立即使在途 HTTP Sync 响应失效，避免旧账号响应写入新账号数据库。
  void invalidateSession() {
    _sessionGeneration++;
    _syncTask = null;
    _trailingSyncRequested = false;
    _trailingReason = null;
    _realtimeSubscribed = false;
  }

  /// 当前用户频道是否已经完成服务端订阅确认。
  ///
  /// 该状态仅用于同步诊断；断线期间不再据此启动 `/sync` 轮询。
  bool get realtimeSubscribed => _realtimeSubscribed;

  void setRealtimeSubscribed(bool value) {
    _realtimeSubscribed = value;
  }

  /// 只发布已成功写入 SQLite 的事件，页面不会看到未持久化状态。
  Stream<Map<String, dynamic>> get appliedEvents => _appliedEvents.stream;

  /// 提交一次同步意图，并在进程内全局合并并发请求。
  ///
  /// [afterCurrent] 用于 WebSocket 订阅完成等同步屏障：如果 HTTP 同步已经在
  /// 执行，则在其完成后至多追加一轮，关闭请求期间可能产生的消息缺口。
  Future<ImSyncResult> requestSync({
    required ImSyncReason reason,
    bool afterCurrent = false,
    int limit = 200,
  }) {
    final running = _syncTask;
    if (running != null) {
      _trailingSyncRequested = true;
      _trailingReason = reason;
      LogUtil.d(
        'reason=${reason.name} action=queue-trailing',
        tag: 'IM sync coordinator',
      );
      return running;
    }
    final task = _runCoordinatedSync(
      reason: reason,
      limit: limit,
      generation: _sessionGeneration,
    );
    _syncTask = task;
    task.then<void>(
      (_) {
        if (identical(_syncTask, task)) _syncTask = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_syncTask, task)) _syncTask = null;
      },
    );
    return task;
  }

  /// 兼容现有内部调用；新增业务入口必须传入明确的同步原因。
  Future<ImSyncResult> syncOnce({int limit = 200}) =>
      requestSync(reason: ImSyncReason.manual, limit: limit);

  Future<ImSyncResult> _runCoordinatedSync({
    required ImSyncReason reason,
    required int limit,
    required int generation,
  }) async {
    var currentReason = reason;
    late ImSyncResult result;
    do {
      _trailingSyncRequested = false;
      _trailingReason = null;
      final stopwatch = Stopwatch()..start();
      LogUtil.d(
        'reason=${currentReason.name} action=start realtime_subscribed=$_realtimeSubscribed',
        tag: 'IM sync coordinator',
      );
      try {
        result = await _syncOnceInternal(limit: limit, generation: generation);
        LogUtil.d(
          'reason=${currentReason.name} action=complete '
          'duration_ms=${stopwatch.elapsedMilliseconds} '
          'events=${result.events.length}',
          tag: 'IM sync coordinator',
        );
      } catch (error) {
        LogUtil.d(
          'reason=${currentReason.name} action=failed '
          'duration_ms=${stopwatch.elapsedMilliseconds} error=$error',
          tag: 'IM sync coordinator',
        );
        rethrow;
      }
      currentReason = _trailingReason ?? currentReason;
    } while (_trailingSyncRequested);
    return result;
  }

  Future<ImSyncResult> _syncOnceInternal({
    int limit = 200,
    bool isRepairing = false,
    required int generation,
  }) async {
    final user = await _storage.readUser();
    if (user == null) {
      return const ImSyncResult(nextCursor: '0', events: [], messages: []);
    }
    final device = await _deviceService.requestPayload();
    final deviceId = device['device_id'] as String;
    if (!isRepairing &&
        _directorySync != null &&
        !await _database.hasDirectoryState('core_snapshot_complete')) {
      final barrier = await _directorySync.bootstrapIfRequired();
      await _database.advanceSyncCursor(
        userId: user.id,
        deviceId: deviceId,
        nextCursor: barrier,
      );
    }
    var cursor = await _database.readSyncCursor(
      userId: user.id,
      deviceId: deviceId,
    );
    final events = <Map<String, dynamic>>[];
    final messages = <MessageModel>[];

    while (true) {
      late final ImSyncResult page;
      try {
        page = await _repository.sync(
          cursor: cursor,
          deviceId: deviceId,
          limit: limit,
        );
      } on ApiException catch (error) {
        final resetRequired =
            error.code == 'SYNC_RESET_REQUIRED' ||
            error.code == 'IM_SYNC_CURSOR_EXPIRED';
        if (!resetRequired || isRepairing) rethrow;
        if (!await _isSessionCurrent(user.id, generation)) {
          return ImSyncResult(
            nextCursor: cursor,
            events: events,
            messages: messages,
          );
        }
        await _database.resetRebuildableCache();
        final directorySync = _directorySync;
        if (directorySync != null) {
          final barrier = await directorySync.bootstrapIfRequired(force: true);
          await _database.advanceSyncCursor(
            userId: user.id,
            deviceId: deviceId,
            nextCursor: barrier,
          );
        }
        return _syncOnceInternal(
          limit: limit,
          isRepairing: true,
          generation: generation,
        );
      }
      if (!await _isSessionCurrent(user.id, generation)) {
        return ImSyncResult(
          nextCursor: cursor,
          events: events,
          messages: messages,
        );
      }
      LogUtil.d(
        'cursor=$cursor next_cursor=${page.nextCursor} '
        'events=${page.events.length} has_more=${page.hasMore} '
        'repairing=$isRepairing',
        tag: 'IM sync',
      );
      _validateSyncPage(page, afterCursor: cursor);
      final applyResults = <ImEventApplyResult>[];
      Map<String, dynamic>? failedEvent;
      try {
        await _database.directoryTransaction(
          expectedUserId: user.id,
          action: (transaction) async {
            for (final event in page.events) {
              failedEvent = event;
              LogUtil.d(
                'event_id=${event['event_id'] ?? '-'} '
                'type=${event['event_type'] ?? '-'} '
                'conversation_id=${event['conversation_id'] ?? '-'} '
                'message_id=${event['message_id'] ?? '-'}',
                tag: 'IM sync',
              );
              final result = await _reducer.applyInTransaction(
                transaction,
                userId: user.id,
                event: event,
              );
              applyResults.add(result);
            }
            await _database.advanceSyncCursorInTransaction(
              transaction,
              userId: user.id,
              deviceId: deviceId,
              nextCursor: page.nextCursor,
            );
          },
        );
      } on UnsupportedImEventException {
        final event = failedEvent ?? const <String, dynamic>{};
        await _retainRejectedSyncEvent(user.id, event);
        await _reportProtocolIssue(
          event: 'unknown_push_event',
          envelope: event,
          field: 'event_type',
        );
        rethrow;
      } on FormatException {
        final event = failedEvent ?? const <String, dynamic>{};
        await _retainRejectedSyncEvent(user.id, event);
        await _reportProtocolIssue(
          event: 'invalid_push_event',
          envelope: event,
          field: 'event_payload',
        );
        rethrow;
      }
      for (final result in applyResults) {
        await _reducer.publish(result);
      }
      // 每页事件与权威游标提交后才通知页面。
      for (final event in page.events) {
        _appliedEvents.add(event);
      }
      events.addAll(page.events);
      messages.addAll(page.messages);

      if (!page.hasMore) {
        return ImSyncResult(
          nextCursor: page.nextCursor,
          events: events,
          messages: messages,
        );
      }
      if (page.nextCursor == cursor) {
        await _protocolReporter?.report(
          event: 'invalid_sync_cursor',
          context: const {'field': 'next_cursor'},
        );
        throw const FormatException('IM 同步 has_more=true 但 next_cursor 未推进');
      }
      cursor = page.nextCursor;
    }
  }

  Future<bool> _isSessionCurrent(String userId, int generation) async {
    if (generation != _sessionGeneration) return false;
    return (await _storage.readUser())?.id == userId;
  }

  void _validateSyncPage(ImSyncResult page, {required String afterCursor}) {
    var previous = BigInt.tryParse(afterCursor);
    final next = BigInt.tryParse(page.nextCursor);
    if (previous == null ||
        previous.isNegative ||
        next == null ||
        next.isNegative) {
      throw const FormatException('IM 同步游标必须为非负十进制字符串');
    }
    final nextValue = next;
    var previousValue = previous;
    for (final event in page.events) {
      final current = BigInt.tryParse(event['event_id']?.toString() ?? '');
      if (current == null || current <= previousValue) {
        throw const FormatException('IM 同步事件必须按event_id严格升序返回');
      }
      previousValue = current;
    }
    if (nextValue < previousValue) {
      throw const FormatException('IM next_cursor不能小于本页最后event_id');
    }
  }

  /// 实时事件与增量同步共用事件归约器，但不推进 REST 权威游标。
  /// 重连后的 `/sync` 会幂等补偿，并使用服务端 next_cursor 推进游标。
  Future<ImEventApplyResult?> applyRealtimeEvent(
    Map<String, dynamic> event,
  ) async {
    final user = await _storage.readUser();
    if (user == null) return null;
    late final ImEventApplyResult result;
    try {
      result = await _reducer.apply(userId: user.id, event: event);
    } on UnsupportedImEventException {
      await _reportProtocolIssue(
        event: 'unknown_push_event',
        envelope: event,
        field: 'event_type',
      );
      rethrow;
    } on FormatException {
      await _reportProtocolIssue(
        event: 'invalid_push_event',
        envelope: event,
        field: 'event_payload',
      );
      rethrow;
    }
    _appliedEvents.add(event);
    return result;
  }

  /// HTTP 写接口返回的 Event 与实时事件共用归约器，但不推进可靠同步游标。
  Future<ImEventApplyResult?> applyWriteThroughEvent(
    Map<String, dynamic> event,
  ) => applyRealtimeEvent(event);

  Future<void> _retainRejectedSyncEvent(
    String userId,
    Map<String, dynamic> event,
  ) async {
    final eventId = event['event_id']?.toString().trim() ?? '';
    if (eventId.isEmpty) return;
    await _database.retainUnsupportedEvent(
      userId: userId,
      eventId: eventId,
      eventType: event['event_type']?.toString() ?? 'invalid',
      rawEvent: event,
    );
  }

  Future<void> _reportProtocolIssue({
    required String event,
    required Map<String, dynamic> envelope,
    required String field,
  }) async {
    final eventName = envelope['event_type']?.toString() ?? 'missing';
    await _protocolReporter?.report(
      event: event,
      context: {'event_name': eventName, 'field': field},
    );
  }
}


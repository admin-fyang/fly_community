/// 社区版通讯录全量校准服务。
library;

import 'dart:async';

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../local/im_local_database.dart';
import '../local/session_storage.dart';
import '../models/directory_models.dart';

/// 目录请求发起时的账号身份与会话代次。
///
/// Repository 必须在 HTTP 请求前捕获该令牌，并在响应写入 SQLite 时原样传回，
/// 防止退出登录后的旧响应写进新账号数据库。
class DirectorySyncToken {
  const DirectorySyncToken._(this.userId, this.generation);

  final String userId;
  final int generation;
}

class DirectorySyncService {
  DirectorySyncService(this._client, this._database, this._storage);

  final ApiClient _client;
  final ImLocalDatabase _database;
  final SessionStorage _storage;
  Future<void>? _running;
  int? _runningGeneration;
  bool _runningForced = false;
  bool _forcePending = false;
  int _generation = 0;
  StreamSubscription<Map<String, dynamic>>? _legacyEventSubscription;
  Future<void> Function(Map<String, dynamic> event)? _applyWriteThroughEvent;
  Future<void> Function()? _requestIncrementalSync;

  void bindReliableSync({
    required Future<void> Function(Map<String, dynamic> event)
    applyWriteThroughEvent,
    required Future<void> Function() requestIncrementalSync,
  }) {
    _applyWriteThroughEvent = applyWriteThroughEvent;
    _requestIncrementalSync = requestIncrementalSync;
  }

  /// 退出登录时立即使所有在途目录响应失效。
  ///
  /// HTTP 请求无法保证已经从系统网络栈取消，因此真正的数据隔离必须依靠令牌
  /// 校验；清空 [_running] 还允许新账号无需等待旧账号请求超时即可开始校准。
  void invalidateSession() {
    _generation++;
    _forcePending = false;
    _running = null;
    _runningGeneration = null;
    _runningForced = false;
  }

  Future<DirectorySyncToken?> captureToken() async {
    final userId = (await _storage.readUser())?.id.trim() ?? '';
    if (userId.isEmpty) return null;
    return DirectorySyncToken._(userId, _generation);
  }

  Future<bool> _isCurrent(DirectorySyncToken token) async {
    if (token.generation != _generation) return false;
    final userId = (await _storage.readUser())?.id.trim() ?? '';
    return userId.isNotEmpty && userId == token.userId;
  }

  /// 迁移期兜底：历史服务路径可能仍只发送旧conversation_updated字段。
  /// 一旦服务端事件已携带directory_changes，本分支完全不产生额外请求。
  void bindAppliedEvents(Stream<Map<String, dynamic>> events) {
    _legacyEventSubscription ??= events.listen((event) {
      if (event['event_type']?.toString() != 'conversation_updated') return;
      final payload = event['payload'];
      if (payload is! Map) return;
      final changes = payload['directory_changes'];
      if (changes is List && changes.isNotEmpty) return;
      final reason = payload['reason']?.toString() ?? '';
      if (reason.startsWith('contact_')) {
        unawaited(_repairLegacyEvent());
      }
    });
  }

  Future<void> _repairLegacyEvent() async {
    try {
      final token = await captureToken();
      if (token == null) return;
      await _requestIncrementalSync?.call();
    } catch (_) {
      // 旧事件修复失败时保留现有缓存；下一次前台校准或手动刷新会继续重试。
    }
  }

  Future<void> calibrateIfNeeded({
    bool force = false,
    DirectorySyncToken? token,
  }) async {
    final operationToken = token ?? await captureToken();
    if (operationToken == null || !await _isCurrent(operationToken)) return;
    final running = _running;
    if (running != null && _runningGeneration == operationToken.generation) {
      // 已在执行强制快照时，其他页面进入只需共享同一任务；只有当前运行
      // 是普通按需校准时，才追加一轮强制请求。
      if (force && !_runningForced) _forcePending = true;
      return running;
    }
    late final Future<void> task;
    task = (() async {
      try {
        var runForced = force;
        do {
          _forcePending = false;
          _runningForced = runForced;
          await _calibrateIfNeeded(token: operationToken, force: runForced);
          if (!await _isCurrent(operationToken)) return;
          runForced = _forcePending;
        } while (runForced);
      } catch (_) {
        // 账号变化属于正常取消，不得让旧请求错误污染新账号页面状态。
        if (await _isCurrent(operationToken)) rethrow;
      } finally {
        if (identical(_running, task)) {
          _running = null;
          _runningGeneration = null;
          _runningForced = false;
          _forcePending = false;
        }
      }
    })();
    _running = task;
    _runningGeneration = operationToken.generation;
    return task;
  }

  Future<void> _calibrateIfNeeded({
    required DirectorySyncToken token,
    required bool force,
  }) async {
    if (!await _isCurrent(token)) return;
    if (!force && await _database.hasDirectoryState('core_snapshot_complete')) {
      return;
    }

    String? cursor;
    String? barrierEventId;
    final visited = <String>{};
    do {
      final page = await _client.get<DirectoryBootstrapPage>(
        _withQuery(ApiPaths.imDirectoryBootstrap, {
          'limit': '200',
          if (cursor != null) 'cursor': cursor,
        }),
        decoder: (data) => DirectoryBootstrapPage.fromJson(_object(data)),
      );
      if (!await _isCurrent(token)) return;
      if (barrierEventId != null && page.barrierEventId != barrierEventId) {
        throw const FormatException('目录分页barrier_event_id发生变化');
      }
      barrierEventId = page.barrierEventId;
      await _database.applyDirectorySnapshotPage(
        page,
        expectedUserId: token.userId,
      );
      if (!page.hasMore) {
        await _database.markCoreDirectoryCalibrated(
          snapshotRevision: page.barrierEventId,
          barrierEventId: page.barrierEventId,
          expectedUserId: token.userId,
        );
        return;
      }
      final next = page.nextCursor?.trim() ?? '';
      if (next.isEmpty || next == cursor || !visited.add(next)) {
        throw const FormatException('目录分页游标未推进');
      }
      cursor = next;
    } while (true);
  }

  /// 修改接口成功后立即写穿，随后到达的同event_id实时事件会被修订表幂等挡住。
  Future<void> applyMutationResponse(
    Map<String, dynamic> response, {
    DirectorySyncToken? token,
    bool calibrateWhenMissing = true,
  }) async {
    final operationToken = token ?? await captureToken();
    if (operationToken == null || !await _isCurrent(operationToken)) return;
    final rawEvent = response['event'];
    if (rawEvent is Map) {
      final event = rawEvent.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final applyEvent = _applyWriteThroughEvent;
      if (applyEvent == null) {
        throw StateError('可靠同步事件归约器尚未绑定');
      }
      await applyEvent(event);
      return;
    }
    final revision = response['directory_revision']?.toString().trim() ?? '';
    final raw = response['directory_changes'];
    if (BigInt.tryParse(revision) == null || raw is! List) {
      if (calibrateWhenMissing) {
        await _requestIncrementalSync?.call();
      }
      return;
    }
    if (raw.isEmpty) return;
    final changes = raw
        .map((item) {
          if (item is! Map) throw const FormatException('目录变更响应格式不正确');
          return DirectoryChange.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: false);
    var changed = false;
    await _database.directoryTransaction(
      expectedUserId: operationToken.userId,
      action: (transaction) async {
        changed = await _database.applyDirectoryChangesInTransaction(
          transaction,
          changes: changes,
          revision: revision,
        );
      },
    );
    if (changed) await _database.publishDirectoryChange();
  }

  /// 首次本地无目录或 Reset Recovery 时建立权威快照，并返回同步屏障水位。
  Future<String> bootstrapIfRequired({bool force = false}) async {
    await calibrateIfNeeded(force: force);
    final barrier =
        await _database.readDirectoryStateValue('core_barrier_event_id') ?? '';
    final parsed = BigInt.tryParse(barrier);
    if (parsed == null || parsed.isNegative) {
      throw const FormatException('目录Bootstrap缺少有效barrier_event_id');
    }
    return barrier;
  }

  Future<void> requestIncrementalSync() async {
    final request = _requestIncrementalSync;
    if (request == null) {
      throw StateError('可靠增量同步协调器尚未绑定');
    }
    await request();
  }

}

String _withQuery(String path, Map<String, String> query) =>
    Uri(path: path, queryParameters: query).toString();

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('data必须为JSON对象');
}

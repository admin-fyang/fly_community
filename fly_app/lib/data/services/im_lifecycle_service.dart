/// IM 应用生命周期协调服务。
///
/// Centrifugo 负责实时性，HTTP Incremental Sync 负责可靠日志对账。
/// 本服务在启动、回前台与真实重连时提交同步意图，所有意图由唯一协调器合并。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/network/network_recovery_controller.dart';
import '../../core/network/api_exception.dart';
import '../local/im_local_database.dart';
import '../local/session_storage.dart';
import 'android_local_notification_service.dart';
import 'directory_sync_service.dart';
import 'im_pending_message_service.dart';
import 'im_realtime_service.dart';
import 'im_sync_service.dart';

/// 一次 IM 会话激活中各独立子任务的结果。
class ImActivationResult {
  const ImActivationResult({
    required this.syncReady,
    required this.pendingRetryReady,
    required this.realtimeStarted,
    this.wasCancelled = false,
  });

  const ImActivationResult.ready()
    : syncReady = true,
      pendingRetryReady = true,
      realtimeStarted = true,
      wasCancelled = false;

  const ImActivationResult.cancelled()
    : syncReady = false,
      pendingRetryReady = false,
      realtimeStarted = false,
      wasCancelled = true;

  final bool syncReady;
  final bool pendingRetryReady;
  final bool realtimeStarted;
  final bool wasCancelled;

  bool get shouldWarnSync => !wasCancelled && !syncReady;
}

class ImLifecycleService with WidgetsBindingObserver {
  ImLifecycleService(
    SessionStorage storage,
    ImSyncService syncService,
    ImRealtimeService realtimeService,
    ImPendingMessageService pendingMessageService,
    ImLocalDatabase database, [
    DirectorySyncService? directorySyncService,
    AndroidLocalNotificationService? localNotificationService,
    this.networkRecovery,
  ]) : _hasSession = storage.hasSession,
       _requestSync = ((reason, {afterCurrent = false}) async {
         await syncService.requestSync(
           reason: reason,
           afterCurrent: afterCurrent,
         );
       }),
       _subscriptionResults = realtimeService.subscriptionResults,
       _realtimeDiagnostics = realtimeService.diagnostics,
       _connectivityChanges = Connectivity().onConnectivityChanged,
       _startRealtime = realtimeService.start,
       _waitForSubscriptionResult = realtimeService.waitForSubscriptionResult,
       _setRealtimeSubscribed = syncService.setRealtimeSubscribed,
       _stopRealtime = realtimeService.stop,
       _retryPendingMessages = pendingMessageService.retryPending,
       _invalidateDirectorySession = (() {
         syncService.invalidateSession();
         directorySyncService?.invalidateSession();
       }),
       _prepareLocalNotifications =
           localNotificationService?.initialize ?? (() async {}),
       _closeDatabase = database.close;

  /// 仅为生命周期时序测试提供可控边界。
  @visibleForTesting
  ImLifecycleService.forTesting({
    this.networkRecovery,
    required Future<bool> Function() hasSession,
    required Future<void> Function() syncOnce,
    required Stream<ImRealtimeSubscriptionResult> subscriptionResults,
    Stream<ImRealtimeDiagnostic> realtimeDiagnostics =
        const Stream<ImRealtimeDiagnostic>.empty(),
    Stream<List<ConnectivityResult>> connectivityChanges =
        const Stream<List<ConnectivityResult>>.empty(),
    required Future<bool> Function() startRealtime,
    Future<ImRealtimeSubscriptionResult?> Function(Duration timeout)?
    waitForSubscriptionResult,
    required Future<void> Function() stopRealtime,
    required Future<void> Function() retryPendingMessages,
    void Function()? invalidateDirectorySession,
    required Future<void> Function() closeDatabase,
  }) : _hasSession = hasSession,
       _requestSync = ((_, {afterCurrent = false}) => syncOnce()),
       _subscriptionResults = subscriptionResults,
       _realtimeDiagnostics = realtimeDiagnostics,
       _connectivityChanges = connectivityChanges,
       _startRealtime = startRealtime,
       _waitForSubscriptionResult =
           waitForSubscriptionResult ?? ((_) async => null),
       _setRealtimeSubscribed = ((_) {}),
       _stopRealtime = stopRealtime,
       _retryPendingMessages = retryPendingMessages,
       _invalidateDirectorySession = invalidateDirectorySession ?? (() {}),
       _prepareLocalNotifications = (() async {}),
       _closeDatabase = closeDatabase;

  final NetworkRecoveryController? networkRecovery;
  final Future<bool> Function() _hasSession;
  final Future<void> Function(ImSyncReason reason, {bool afterCurrent})
  _requestSync;
  final Stream<ImRealtimeSubscriptionResult> _subscriptionResults;
  final Stream<ImRealtimeDiagnostic> _realtimeDiagnostics;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  final Future<bool> Function() _startRealtime;
  final Future<ImRealtimeSubscriptionResult?> Function(Duration timeout)
  _waitForSubscriptionResult;
  final void Function(bool value) _setRealtimeSubscribed;
  final Future<void> Function() _stopRealtime;
  final Future<void> Function() _retryPendingMessages;
  final void Function() _invalidateDirectorySession;
  final Future<void> Function() _prepareLocalNotifications;
  final Future<void> Function() _closeDatabase;

  Future<ImActivationResult>? _activationTask;
  StreamSubscription<ImRealtimeSubscriptionResult>? _subscriptionSubscription;
  StreamSubscription<ImRealtimeDiagnostic>? _diagnosticSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ImRealtimeSubscriptionResult? _subscriptionDuringActivation;
  bool _isObserving = false;
  bool _sessionActive = false;
  bool _isRealtimeSubscribed = false;
  bool _wasOffline = false;
  AppLifecycleState? _lastLifecycleState;
  String _networkSummary = 'unknown';
  Timer? _healthSyncTimer;
  int _sessionGeneration = 0;

  /// 观察真实订阅建立/恢复结果；每次重连都请求一次可靠日志对账。
  void startObserving() {
    if (_isObserving) return;
    _isObserving = true;
    unawaited(
      networkRecovery?.initializeConnectivity(() async {
        final results = await Connectivity().checkConnectivity();
        return results.isEmpty ||
            results.every((item) => item == ConnectivityResult.none);
      }),
    );
    WidgetsBinding.instance.addObserver(this);
    _subscriptionSubscription = _subscriptionResults.listen((result) {
      if (!_sessionActive) return;
      _updateRealtimeSubscribed(true);
      networkRecovery?.realtimeResult(true);
      if (_activationTask != null) {
        _subscriptionDuringActivation = result;
        return;
      }
      unawaited(_recoverAfterSubscription(result));
    });
    _diagnosticSubscription = _realtimeDiagnostics.listen((diagnostic) {
      if (!_sessionActive) return;
      switch (diagnostic.status) {
        case ImRealtimeStatus.subscribed:
          _updateRealtimeSubscribed(true);
          networkRecovery?.realtimeResult(true);
        case ImRealtimeStatus.connecting:
        case ImRealtimeStatus.connected:
          // 首次握手尚未建立订阅不算失败；已订阅连接丢失则立即显示异常。
          if (_isRealtimeSubscribed) networkRecovery?.realtimeResult(false);
          _updateRealtimeSubscribed(false);
        case ImRealtimeStatus.unsubscribed:
        case ImRealtimeStatus.disconnected:
        case ImRealtimeStatus.tokenError:
        case ImRealtimeStatus.stopped:
          _updateRealtimeSubscribed(false);
          networkRecovery?.realtimeResult(false);
        case ImRealtimeStatus.protocolError:
          // 已订阅时单个协议消息错误不等同断网；失败重连则不能悄悄隐藏。
          if (!_isRealtimeSubscribed) networkRecovery?.realtimeResult(false);
      }
    });
    _connectivitySubscription = _connectivityChanges.listen((results) {
      final previousNetwork = _networkSummary;
      _networkSummary = results.isEmpty
          ? 'none'
          : results.map((item) => item.name).join(',');
      final offline =
          results.isEmpty ||
          results.every((item) => item == ConnectivityResult.none);
      networkRecovery?.updateConnectivity(offline);
      final interfaceChanged =
          previousNetwork != 'unknown' && previousNetwork != _networkSummary;
      if ((_wasOffline || interfaceChanged) && !offline && _sessionActive) {
        unawaited(networkRecovery?.retry(reconnectTransport: false));
        unawaited(_recoverAfterNetworkRestored());
      }
      _wasOffline = offline;
    });
    _healthSyncTimer = Timer.periodic(const Duration(minutes: 25), (_) {
      if (!_sessionActive) return;
      unawaited(
        _performSync(
          'health-sync',
          ImSyncReason.healthCheck,
          afterCurrent: true,
        ),
      );
    });
  }

  @visibleForTesting
  Future<void> stopObserving() async {
    if (!_isObserving) return;
    _isObserving = false;
    WidgetsBinding.instance.removeObserver(this);
    await _subscriptionSubscription?.cancel();
    _subscriptionSubscription = null;
    await _diagnosticSubscription?.cancel();
    _diagnosticSubscription = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _healthSyncTimer?.cancel();
    _healthSyncTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[IM lifecycle] ${_lastLifecycleState?.name ?? 'unknown'} -> '
      '${state.name} session_active=$_sessionActive '
      'realtime_subscribed=$_isRealtimeSubscribed network=$_networkSummary',
    );
    _lastLifecycleState = state;
    switch (state) {
      case AppLifecycleState.resumed:
        if (_sessionActive) {
          unawaited(_resumeRealtime());
        } else {
          unawaited(activateSession());
        }
      case AppLifecycleState.detached:
        // detached 表示 Flutter View 当前未附着，不等于用户退出登录或进程
        // 已经销毁。真正进程退出无需主动清理；配置切换或 Activity 重建时
        // stop 反而会制造后台断线。实时连接只允许 deactivateSession 停止。
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // 短暂离开前台时保留 SDK 客户端，由 Centrifugo 自行维持或恢复连接。
        break;
    }
  }

  Future<void> _resumeRealtime() async {
    try {
      await _startRealtime();
    } catch (error, stackTrace) {
      _logStageFailure('resume-realtime', error, stackTrace);
    }
    await _performSync('resume-sync', ImSyncReason.resume, afterCurrent: true);
    unawaited(networkRecovery?.retry(reconnectTransport: false));
  }

  /// Android 前台服务已确认独立订阅后，释放主 Isolate 的重复连接。
  ///
  /// 这里只切换实时传输所有权，不清会话、不关数据库，也不停止可靠同步。
  Future<void> handoffRealtimeToForegroundService() async {
    if (!_sessionActive) return;
    await _stopRealtime();
    _updateRealtimeSubscribed(false);
  }

  /// 页面回到前台时先恢复主连接并完成一次可靠对账。
  ///
  /// 返回 true 后调用方才能让后台 Isolate 断开，避免切换窗口完全无连接。
  Future<bool> reclaimRealtimeFromForegroundService() async {
    if (!_sessionActive) return false;
    try {
      final started = await _startRealtime();
      if (!started) return false;
      final subscribed = await _waitForSubscriptionResult(
        const Duration(seconds: 3),
      );
      if (subscribed == null) return false;
      await _performSync(
        'foreground-service-handoff-sync',
        ImSyncReason.resume,
        afterCurrent: true,
      );
      return true;
    } catch (error, stackTrace) {
      _logStageFailure('foreground-service-reclaim', error, stackTrace);
      return false;
    }
  }

  /// 顶部连接标识的主动恢复入口，复用实时连接与可靠同步协调器。
  Future<void> retryConnection() async {
    if (!_sessionActive) return;
    final generation = _sessionGeneration;
    try {
      await _startRealtime();
    } catch (error, stackTrace) {
      _logStageFailure('manual-realtime', error, stackTrace);
    }
    if (generation != _sessionGeneration) return;
    await _requestSync(ImSyncReason.manual, afterCurrent: true);
  }

  Future<void> _recoverAfterNetworkRestored() async {
    try {
      await _startRealtime();
    } catch (error, stackTrace) {
      _logStageFailure('network-realtime', error, stackTrace);
    }
    await _performSync(
      'network-restored-sync',
      ImSyncReason.networkRestored,
      afterCurrent: true,
    );
  }

  /// 激活当前登录会话。Realtime 恢复结果只影响原因，不再决定是否跳过 HTTP Sync。
  Future<ImActivationResult> activateSession() {
    final running = _activationTask;
    if (running != null) return running;
    final generation = _sessionGeneration;
    _subscriptionDuringActivation = null;
    final task = _activateSession(generation);
    _activationTask = task;

    void finish() {
      if (!identical(_activationTask, task)) return;
      _activationTask = null;
      final pending = _subscriptionDuringActivation;
      _subscriptionDuringActivation = null;
      if (pending != null && _sessionActive) {
        unawaited(_recoverContinuityGap(pending));
      }
    }

    task.then<void>(
      (_) => finish(),
      onError: (Object _, StackTrace __) => finish(),
    );
    return task;
  }

  Future<ImActivationResult> _activateSession(int generation) async {
    try {
      if (!await _hasSession()) {
        _sessionActive = false;
        return const ImActivationResult.ready();
      }
    } catch (error, stackTrace) {
      _logStageFailure('session', error, stackTrace);
      return const ImActivationResult(
        syncReady: false,
        pendingRetryReady: false,
        realtimeStarted: false,
      );
    }
    if (generation != _sessionGeneration) {
      return const ImActivationResult.cancelled();
    }
    _sessionActive = true;
    // 系统权限弹窗不能阻塞实时连接；初始化与授权失败也不能让 IM 会话失败。
    unawaited(
      _prepareLocalNotifications().catchError((Object error) {
        debugPrint('[IM notification] 权限初始化失败：$error');
      }),
    );

    var realtimeStarted = true;
    ImRealtimeSubscriptionResult? subscriptionResult;
    try {
      debugPrint('[IM lifecycle][realtime] 实时连接启动');
      realtimeStarted = await _startRealtime();
      if (realtimeStarted) {
        subscriptionResult = await _waitForSubscriptionResult(
          const Duration(seconds: 2),
        );
      }
      if (identical(_subscriptionDuringActivation, subscriptionResult)) {
        _subscriptionDuringActivation = null;
      }
      debugPrint(
        '[IM lifecycle][realtime] 启动结果：$realtimeStarted '
        'recovered=${subscriptionResult?.continuityRecovered}',
      );
    } catch (error, stackTrace) {
      realtimeStarted = false;
      _logStageFailure('realtime', error, stackTrace);
    }
    if (generation != _sessionGeneration) {
      return const ImActivationResult.cancelled();
    }

    var syncReady = true;
    final syncReason = subscriptionResult == null
        ? ImSyncReason.bootstrapTimeout
        : _syncReasonFor(subscriptionResult);
    try {
      debugPrint('[IM lifecycle][sync] 可靠增量对账开始：$syncReason');
      await _requestSync(syncReason);
      if (generation == _sessionGeneration) {
        networkRecovery?.connectionResult(true);
      }
      debugPrint('[IM lifecycle][sync] 可靠增量对账完成');
    } catch (error, stackTrace) {
      syncReady = false;
      _logStageFailure('sync', error, stackTrace);
    }
    if (generation != _sessionGeneration) {
      return const ImActivationResult.cancelled();
    }

    var pendingRetryReady = true;
    try {
      await _retryPendingMessages();
    } catch (error, stackTrace) {
      pendingRetryReady = false;
      _logStageFailure('pending', error, stackTrace);
    }

    if (generation != _sessionGeneration) {
      return const ImActivationResult.cancelled();
    }

    final pendingSubscription = _subscriptionDuringActivation;
    _subscriptionDuringActivation = null;
    if (pendingSubscription != null) {
      final recovered = await _recoverContinuityGap(pendingSubscription);
      syncReady = syncReady && recovered;
    }

    return ImActivationResult(
      syncReady: syncReady,
      pendingRetryReady: pendingRetryReady,
      realtimeStarted: realtimeStarted,
    );
  }

  ImSyncReason _syncReasonFor(ImRealtimeSubscriptionResult result) {
    if (result.wasRecovering && !result.continuityRecovered) {
      return ImSyncReason.recoveryFailed;
    }
    return result.wasRecovering
        ? ImSyncReason.realtimeReconnected
        : ImSyncReason.initialSubscription;
  }

  Future<bool> _recoverContinuityGap(
    ImRealtimeSubscriptionResult result,
  ) async {
    final reason = _syncReasonFor(result);
    return _performSync(
      'subscription-recovery-sync',
      reason,
      afterCurrent: true,
    );
  }

  Future<void> _recoverAfterSubscription(
    ImRealtimeSubscriptionResult result,
  ) async {
    await _recoverContinuityGap(result);
    unawaited(networkRecovery?.retry(reconnectTransport: false));
    try {
      await _retryPendingMessages();
    } catch (error, stackTrace) {
      _logStageFailure('subscription-pending-message', error, stackTrace);
    }
  }

  void _logStageFailure(String stage, Object error, StackTrace stackTrace) {
    debugPrint('[IM lifecycle][$stage] 初始化失败：$error');
    debugPrint('[IM lifecycle][$stage] stack\n$stackTrace');
  }

  /// 退出登录才销毁实时客户端；账号切换通过 generation 取消旧激活任务。
  Future<void> deactivateSession() async {
    ++_sessionGeneration;
    networkRecovery?.resetSession();
    _activationTask = null;
    _subscriptionDuringActivation = null;
    _sessionActive = false;
    _invalidateDirectorySession();
    _updateRealtimeSubscribed(false);
    // 通话插件异常仍必须停止实时连接并关闭数据库，防止已撤销会话继续工作。
    try {
    } finally {
      try {
        await _stopRealtime();
      } finally {
        try {
          await _closeDatabase();
        } catch (_) {
          // 数据库关闭失败不阻止退出登录。
        }
      }
    }
  }

  void _updateRealtimeSubscribed(bool value) {
    if (_isRealtimeSubscribed == value) return;
    _isRealtimeSubscribed = value;
    _setRealtimeSubscribed(value);
  }

  Future<bool> _performSync(
    String stage,
    ImSyncReason reason, {
    bool afterCurrent = false,
  }) async {
    final generation = _sessionGeneration;
    try {
      await _requestSync(reason, afterCurrent: afterCurrent);
      if (generation == _sessionGeneration) {
        networkRecovery?.connectionResult(true);
      }
      return true;
    } catch (error, stackTrace) {
      if (generation == _sessionGeneration &&
          error is ApiException &&
          (error.kind == ApiFailureKind.timeout ||
              error.kind == ApiFailureKind.connection ||
              const {500, 502, 503, 504}.contains(error.statusCode))) {
        networkRecovery?.connectionResult(false);
      }
      _logStageFailure(stage, error, stackTrace);
      return false;
    }
  }
}

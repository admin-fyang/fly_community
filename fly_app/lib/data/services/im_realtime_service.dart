/// Centrifugo 实时连接服务。
///
/// 服务端通过 JWT 或会话鉴权 proxy 自动订阅 `private-user:{user_id}`；客户端只监听
/// 服务端订阅事件，绝不自行拼接或订阅频道。协议握手、Ping/Pong、分帧与退避
/// 重连统一交给 Centrifugo 官方 Dart SDK，业务层只接收已经解码的 IM 事件信封。
library;

import 'dart:async';
import 'dart:convert';

import 'package:centrifuge/centrifuge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../core/network/api_exception.dart';
import '../../domain/repositories/im_repository.dart';
import '../models/im_api_models.dart';
import 'im_protocol_issue_reporter.dart';

/// 实时链路状态，用于日志、测试和后续经确认的断线提示 UI。
enum ImRealtimeStatus {
  stopped,
  connecting,
  connected,
  subscribed,
  unsubscribed,
  disconnected,
  tokenError,
  protocolError,
}

/// 不包含 JWT 的实时链路诊断信息，避免日志泄露连接凭证。
class ImRealtimeDiagnostic {
  const ImRealtimeDiagnostic({
    required this.status,
    required this.message,
    this.code,
  });

  final ImRealtimeStatus status;
  final String message;
  final int? code;
}

/// 一次服务端用户频道订阅的恢复结果。
///
/// 只有 [continuityRecovered] 为 true 才能证明断线期间的 Publication 已由
/// Centrifugo History 完整补齐；首次订阅或恢复失败仍需回源 `/sync`。
class ImRealtimeSubscriptionResult {
  const ImRealtimeSubscriptionResult({
    required this.channel,
    required this.wasRecovering,
    required this.recovered,
    required this.streamPosition,
  });

  final String channel;
  final bool wasRecovering;
  final bool recovered;
  final StreamPosition? streamPosition;

  bool get continuityRecovered => wasRecovering && recovered;
}

/// Centrifugo SDK 客户端工厂。
///
/// 生产环境使用官方 [createClient]；测试通过注入假客户端精确验证多个服务端
/// 订阅的事件隔离，不需要建立真实 WebSocket。
typedef ImRealtimeClientFactory = Client Function(
  String url,
  ClientConfig config,
);

/// 获取一次短期 Centrifugo 连接凭证。
///
/// 主 Isolate 通过 [ImRepository] 提供，Android 前台服务 Isolate 通过自身
/// 的轻量 Dio 客户端提供，从而复用同一套连接、心跳和 Token 刷新实现。
typedef ImRealtimeCredentialLoader =
    Future<CentrifugoConnectionToken> Function();

class ImRealtimeService {
  ImRealtimeService(
    ImRepository repository, [
    this._protocolReporter,
    ImRealtimeClientFactory? clientFactory,
  ]) : _credentialLoader = repository.getCentrifugoToken,
       _clientFactory = clientFactory ?? createClient;

  ImRealtimeService.withCredentialLoader(
    this._credentialLoader, [
    this._protocolReporter,
    ImRealtimeClientFactory? clientFactory,
  ]) : _clientFactory = clientFactory ?? createClient;

  /// 与设备管理后端契约一致的终止断连码，普通断线不能当作账号退出。
  static const sessionRevokedCode = 4501;
  static const sessionRevokedReason = 'AUTH_SESSION_REVOKED';

  /// 可选身份边界保持现有测试/调用兼容，生产主后台连接均由装配层注入。
  Future<String?> Function()? readSessionId;
  Future<void> Function(String sessionId)? onSessionRevoked;
  String? _activeSessionId;
  String? _revokedSessionId;

  static const _credentialRetryDelay = Duration(seconds: 3);

  final ImRealtimeCredentialLoader _credentialLoader;
  final ImProtocolIssueReporter? _protocolReporter;
  final ImRealtimeClientFactory _clientFactory;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _connected = StreamController<void>.broadcast();
  final _diagnostics = StreamController<ImRealtimeDiagnostic>.broadcast();
  // 同步广播保证生命周期协调器先记录本次订阅结果，再唤醒订阅屏障等待者，
  // 避免同一订阅事件被激活流程和重连监听重复补偿。
  final _subscriptionResults =
      StreamController<ImRealtimeSubscriptionResult>.broadcast(sync: true);
  final List<Completer<ImRealtimeSubscriptionResult?>> _subscriptionWaiters =
      [];

  final List<StreamSubscription<dynamic>> _clientSubscriptions = [];
  Client? _client;
  CentrifugoConnectionToken? _credential;
  Future<CentrifugoConnectionToken>? _credentialRequest;
  Future<void>? _refreshTask;
  Timer? _refreshTimer;
  bool _stopped = true;
  bool _subscribed = false;
  String? _connectionId;
  ImRealtimeSubscriptionResult? _lastSubscriptionResult;
  int _clientGeneration = 0;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<void> get connected => _connected.stream;
  Stream<ImRealtimeDiagnostic> get diagnostics => _diagnostics.stream;
  Stream<ImRealtimeSubscriptionResult> get subscriptionResults =>
      _subscriptionResults.stream;
  bool get isSubscribed => _subscribed;

  /// 当前 SDK 状态快照，只用于生命周期诊断，不作为消息一致性依据。
  String get connectionState =>
      _stopped ? 'stopped' : _client?.state.name ?? 'client_missing';

  /// 等待服务端确认用户频道订阅，超时返回 null，不中断 SDK 自身重连。
  Future<ImRealtimeSubscriptionResult?> waitForSubscriptionResult(
    Duration timeout,
  ) async {
    if (_subscribed && _lastSubscriptionResult != null) {
      return _lastSubscriptionResult;
    }
    final waiter = Completer<ImRealtimeSubscriptionResult?>();
    _subscriptionWaiters.add(waiter);
    try {
      return await waiter.future.timeout(timeout, onTimeout: () => null);
    } finally {
      _subscriptionWaiters.remove(waiter);
    }
  }

  /// 启动当前登录会话的实时链路。重复调用不会创建重复连接。
  Future<bool> start() async {
    final owner = await readSessionId?.call();
    if (readSessionId != null &&
        (owner == null || owner == _revokedSessionId)) {
      return false;
    }
    if (_activeSessionId != owner) {
      await stop();
      _credentialRequest = null;
      _refreshTask = null;
    }
    _activeSessionId = owner;
    final existing = _client;
    if (!_stopped && existing != null) {
      if (existing.state != State.disconnected) return true;
      // SDK 的 disconnected 是终止态，不会自动重连。对象仍存在不代表链路
      // 可用；重新获取短期凭证并重建客户端，避免 resumed 误报启动成功。
      try {
        final fresh = await _requestCredential();
        if (_stopped) return false;
        await _installClient(fresh, owner);
        return !_stopped &&
            owner == _activeSessionId &&
            _client != null &&
            _client?.state != State.disconnected;
      } catch (error) {
        _emit(ImRealtimeStatus.tokenError, 'Centrifugo 终止态恢复失败：$error');
        _scheduleCredentialRetry();
        return false;
      }
    }
    _stopped = false;
    try {
      final credential = await _requestCredential();
      if (_stopped) return false;
      await _installClient(credential, owner);
      return !_stopped && owner == _activeSessionId && _client != null;
    } catch (error) {
      if (error is FormatException ||
          (error is ApiException && error.code == 'INVALID_RESPONSE')) {
        unawaited(
          _protocolReporter?.report(
                event: 'invalid_realtime_credential',
                context: const {'field': 'centrifugo_token_response'},
              ) ??
              Future<void>.value(),
        );
      }
      _emit(ImRealtimeStatus.tokenError, 'Centrifugo 凭证获取或校验失败：$error');
      _scheduleCredentialRetry(startWhenMissing: true);
      return false;
    }
  }

  /// 创建 SDK 客户端并绑定所有状态流。
  ///
  /// 每次替换都会增加 generation，旧客户端即使还有异步回调也不能污染新连接。
  Future<void> _installClient(
    CentrifugoConnectionToken credential,
    String? owner,
  ) async {
    final previousGeneration = _clientGeneration;
    if (owner != _activeSessionId || _stopped) return;
    if (readSessionId != null && await readSessionId!() != owner) return;
    if (_stopped ||
        owner != _activeSessionId ||
        previousGeneration != _clientGeneration) {
      return;
    }
    _setSubscribed(false);
    final generation = ++_clientGeneration;
    _refreshTimer?.cancel();
    await _cancelClientSubscriptions();
    if (_stopped ||
        generation != _clientGeneration ||
        owner != _activeSessionId)
      return;
    final previous = _client;
    _client = null;
    if (previous != null) {
      try {
        await previous.close();
      } catch (_) {
        // 旧连接释放失败不应阻止新连接建立。
      }
    }
    if (_stopped || generation != _clientGeneration) return;

    _credential = credential;
    final client = _clientFactory(
      credential.websocketUrl,
      ClientConfig(
        // proxy 模式必须省略协议 token，否则 Centrifugo 会绕过 connect proxy。
        token: credential.authenticationMode == 'proxy' ? '' : credential.token,
        getToken: credential.authenticationMode == 'proxy'
            ? null
            : (_) => _renewTokenForSdk(generation, owner),
        getData: credential.authenticationMode == 'proxy'
            ? () => _proxyConnectionData(generation, owner)
            : null,
        timeout: const Duration(seconds: 10),
        minReconnectDelay: const Duration(milliseconds: 500),
        maxReconnectDelay: const Duration(seconds: 20),
        maxServerPingDelay: const Duration(seconds: 10),
        name: 'fychat-flutter',
      ),
    );
    _client = client;
    _bindClient(client, generation, owner);
    _scheduleRefresh(credential);
    await client.connect();
  }

  void _bindClient(Client client, int generation, String? owner) {
    bool current() =>
        !_stopped &&
        generation == _clientGeneration &&
        identical(client, _client);

    _clientSubscriptions.addAll([
      client.connecting.listen((event) {
        if (!current()) return;
        _emit(
          ImRealtimeStatus.connecting,
          'Centrifugo 正在连接：${event.reason}',
          code: event.code,
        );
      }),
      client.connected.listen((event) {
        if (!current()) return;
        _connectionId = event.client;
        _emit(
          ImRealtimeStatus.connected,
          'Centrifugo 已连接，connection_id=${event.client} '
          'server_version=${event.version}',
        );
      }),
      client.disconnected.listen((event) {
        if (!current()) return;
        if (event.code == sessionRevokedCode &&
            event.reason == sessionRevokedReason) {
          _notifySessionRevoked(owner);
          return;
        }
        _connectionId = null;
        _emit(
          ImRealtimeStatus.disconnected,
          'Centrifugo 已断开：${event.reason}',
          code: event.code,
        );
      }),
      client.error.listen((event) {
        if (!current()) return;
        _emit(
          ImRealtimeStatus.protocolError,
          'Centrifugo SDK 错误：${event.error}',
        );
      }),
      client.subscribed.listen((event) {
        if (!current()) return;
        final expectedChannel = _credential?.channel;
        if (event.channel != expectedChannel) {
          // Connection JWT 可由后端附加 Presence 等辅助服务端订阅。
          // 客户端不感知其频道语义，也不得让它们改变消息主频道状态。
          return;
        }
        // WebSocket connected 不代表用户频道已经可接收 Publication。服务端订阅
        // 结果还包含 History Recovery 是否完整，生命周期层据此决定是否回源。
        _emit(ImRealtimeStatus.subscribed, '服务端订阅已确认：${event.channel}');
        final result = ImRealtimeSubscriptionResult(
          channel: event.channel,
          wasRecovering: event.wasRecovering,
          recovered: event.recovered,
          streamPosition: event.streamPosition,
        );
        _lastSubscriptionResult = result;
        _subscriptionResults.add(result);
        _setSubscribed(true);
        _connected.add(null);
      }),
      client.unsubscribed.listen((event) {
        if (!current()) return;
        if (event.channel != _credential?.channel) return;
        _emit(ImRealtimeStatus.unsubscribed, '服务端订阅已失效：${event.channel}');
      }),
      client.publication.listen((event) {
        if (!current()) return;
        _onPublication(event);
      }),
    ]);
  }

  /// 解码服务端订阅 Publication。频道不匹配或脏数据都不会进入事件归约器。
  void _onPublication(ServerPublicationEvent publication) {
    final expectedChannel = _credential?.channel;
    if (publication.channel != expectedChannel) {
      // 辅助服务端订阅的 Publication 不属于 IM 业务信封，必须静默隔离。
      // 特别是 Presence Join/Leave 不应被普通 Flutter 客户端消费。
      return;
    }
    try {
      final decoded = jsonDecode(utf8.decode(publication.data));
      if (decoded is! Map) {
        throw const FormatException('publication.data 不是 JSON 对象');
      }
      final event = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      _events.add(event);
    } catch (error) {
      unawaited(
        _protocolReporter?.report(
              event: 'invalid_push_event',
              context: const {
                'event_name': 'centrifugo_publication',
                'field': 'publication.data',
              },
            ) ??
            Future<void>.value(),
      );
      _emit(
        ImRealtimeStatus.protocolError,
        'Centrifugo Publication 数据格式错误：$error',
      );
    }
  }

  /// 所有握手和刷新回调在请求前后核对连接代次及本地登录身份。
  /// 不能仅在响应后判定：旧 SDK 回调不得请求或取得新会话的实时凭证。
  Future<void> _assertConnectionOwner(int generation, String? owner) async {
    bool current() =>
        !_stopped &&
        generation == _clientGeneration &&
        owner == _activeSessionId;
    if (!current() ||
        (readSessionId != null && await readSessionId!() != owner) ||
        !current()) {
      throw StateError('实时连接已被替换');
    }
  }

  bool _connectionConfigurationChanged(CentrifugoConnectionToken fresh) =>
      _credential?.websocketUrl != fresh.websocketUrl ||
      _credential?.authenticationMode != fresh.authenticationMode;

  /// 每次 proxy 握手使用有效短期凭证；模式或地址变化必须创建新的 SDK 客户端。
  Future<List<int>> _proxyConnectionData(int generation, String? owner) async {
    await _assertConnectionOwner(generation, owner);
    var credential = _credential;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (credential == null || credential.expiresAt <= now + 10) {
      credential = await _requestCredential();
      await _assertConnectionOwner(generation, owner);
      if (_connectionConfigurationChanged(credential)) {
        await _installClient(credential, owner);
        // 旧握手终止，不把新地址或新模式的凭证交给旧连接。
        throw StateError('实时连接配置已更新');
      }
      _credential = credential;
      _scheduleRefresh(credential);
    }
    if (credential.authenticationMode != 'proxy' ||
        credential.expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const FormatException('实时握手凭证不可用');
    }
    return utf8.encode(jsonEncode({'token': credential.token}));
  }

  /// SDK 刷新仅返回同一连接配置的 JWT，禁止旧回调返回新登录的凭证。
  Future<String> _renewTokenForSdk(int generation, String? owner) async {
    await _assertConnectionOwner(generation, owner);
    try {
      final fresh = await _requestCredential();
      await _assertConnectionOwner(generation, owner);
      if (_connectionConfigurationChanged(fresh)) {
        await _installClient(fresh, owner);
        throw StateError('实时连接配置已更新');
      }
      _credential = fresh;
      _scheduleRefresh(fresh);
      return fresh.token;
    } catch (error) {
      if (!_stopped &&
          generation == _clientGeneration &&
          owner == _activeSessionId) {
        _emit(ImRealtimeStatus.tokenError, 'Centrifugo Token 自动刷新失败：$error');
      }
      rethrow;
    }
  }

  void _scheduleRefresh(CentrifugoConnectionToken credential) {
    _refreshTimer?.cancel();
    if (_stopped) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final seconds = credential.refreshAfter - now;
    _refreshTimer = Timer(
      Duration(seconds: seconds < 1 ? 1 : seconds),
      () => unawaited(_refreshCredential()),
    );
  }

  /// 按后端 refresh_after 主动换取新 Token，并让新 Token 立即用于连接。
  Future<void> _refreshCredential() {
    final running = _refreshTask;
    if (running != null) return running;
    final task = _doRefreshCredential();
    _refreshTask = task;
    task.then<void>(
      (_) {
        if (identical(_refreshTask, task)) _refreshTask = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_refreshTask, task)) _refreshTask = null;
      },
    );
    return task;
  }

  Future<void> _doRefreshCredential() async {
    if (_stopped) return;
    final owner = _activeSessionId;
    final generation = _clientGeneration;
    try {
      await _assertConnectionOwner(generation, owner);
      final fresh = await _requestCredential();
      await _assertConnectionOwner(generation, owner);
      final client = _client;
      final oldUrl = _credential?.websocketUrl;
      if (client == null ||
          oldUrl != fresh.websocketUrl ||
          _credential?.authenticationMode == 'proxy' ||
          fresh.authenticationMode != _credential?.authenticationMode) {
        await _installClient(fresh, owner);
        return;
      }
      _credential = fresh;
      client.setToken(fresh.token);
      _scheduleRefresh(fresh);
      // setToken 更新后续认证凭证；受控重连确保新 Token 立即生效。
      await client.disconnect();
      if (!_stopped && identical(client, _client)) {
        await client.connect();
      }
    } catch (error) {
      if (_stopped ||
          generation != _clientGeneration ||
          owner != _activeSessionId)
        return;
      _emit(ImRealtimeStatus.tokenError, 'Centrifugo 定时刷新失败，稍后重试：$error');
      _scheduleCredentialRetry();
    }
  }

  /// 合并并发的 Token 请求，防止生命周期恢复和 SDK 刷新同时请求接口。
  Future<CentrifugoConnectionToken> _requestCredential() {
    final running = _credentialRequest;
    if (running != null) return running;
    final request = _loadCredentialForSession(
      _activeSessionId,
      _clientGeneration,
    );
    _credentialRequest = request;
    request.then<void>(
      (_) {
        if (identical(_credentialRequest, request)) {
          _credentialRequest = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_credentialRequest, request)) {
          _credentialRequest = null;
        }
      },
    );
    return request;
  }

  Future<CentrifugoConnectionToken> _loadCredentialForSession(
    String? owner,
    int generation,
  ) async {
    try {
      return await _credentialLoader();
    } on ApiException catch (error) {
      if (error.code == sessionRevokedReason &&
          owner == _activeSessionId &&
          generation == _clientGeneration &&
          !_stopped) {
        _notifySessionRevoked(owner);
      }
      rethrow;
    }
  }

  /// 先同步停止重试，再异步通知装配层。事件只携带该连接建立时的会话 ID。
  void _notifySessionRevoked(String? owner) {
    if (owner != _activeSessionId ||
        (owner != null && owner == _revokedSessionId))
      return;
    _revokedSessionId = owner;
    _stopped = true;
    _refreshTimer?.cancel();
    _setSubscribed(false);
    _emit(
      ImRealtimeStatus.disconnected,
      sessionRevokedReason,
      code: sessionRevokedCode,
    );
    final callback = onSessionRevoked;
    if (owner != null && callback != null) callback(owner).ignore();
  }

  void _scheduleCredentialRetry({bool startWhenMissing = false}) {
    _refreshTimer?.cancel();
    if (_stopped) return;
    _refreshTimer = Timer(_credentialRetryDelay, () {
      if (_stopped) return;
      if (startWhenMissing && _client == null) {
        unawaited(start());
      } else {
        unawaited(_refreshCredential());
      }
    });
  }

  void _emit(ImRealtimeStatus status, String message, {int? code}) {
    if (status == ImRealtimeStatus.connecting ||
        status == ImRealtimeStatus.unsubscribed ||
        status == ImRealtimeStatus.disconnected ||
        status == ImRealtimeStatus.tokenError ||
        status == ImRealtimeStatus.stopped) {
      _setSubscribed(false);
    }
    final diagnostic = ImRealtimeDiagnostic(
      status: status,
      message: message,
      code: code,
    );
    _diagnostics.add(diagnostic);
    debugPrint(
      '[IM realtime] ${status.name}${code == null ? '' : '($code)'} '
      'sdk_state=$connectionState subscribed=$_subscribed '
      'lifecycle=${WidgetsBinding.instance.lifecycleState?.name ?? 'unknown'} '
      'connection_id=${_connectionId ?? '-'} $message',
    );
  }

  void _setSubscribed(bool value) {
    if (_subscribed == value) return;
    _subscribed = value;
    if (!value) return;
    final result = _lastSubscriptionResult;
    if (result == null) return;
    final waiters = List<Completer<ImRealtimeSubscriptionResult?>>.of(
      _subscriptionWaiters,
    );
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(result);
    }
  }

  Future<void> _cancelClientSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.of(
      _clientSubscriptions,
    );
    _clientSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  /// 停止连接并释放 SDK 资源；公开事件流保留，供下一次登录继续监听。
  Future<void> stop() async {
    if (_stopped && _client == null) return;
    _stopped = true;
    ++_clientGeneration;
    // 即使下一次仍恢复同一会话，也不能复用上一代连接在途的凭证任务。
    _credentialRequest = null;
    _refreshTask = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _cancelClientSubscriptions();
    final client = _client;
    _client = null;
    _credential = null;
    _connectionId = null;
    _lastSubscriptionResult = null;
    _setSubscribed(false);
    final waiters = List<Completer<ImRealtimeSubscriptionResult?>>.of(
      _subscriptionWaiters,
    );
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    if (client != null) {
      try {
        await client.close();
      } catch (_) {
        // stop 必须可重复调用，释放阶段错误只记录状态，不再抛给生命周期层。
      }
    }
    _emit(ImRealtimeStatus.stopped, 'Centrifugo 实时连接已停止');
  }
}

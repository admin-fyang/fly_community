/// 全局连接反馈与有限恢复协调器。
///
/// 不自行监听网络、不重建 Socket、不保存写入任务。网络类型由既有生命周期
/// 服务提供；HTTP 层只登记已耗尽重试的安全查询。公共顶栏订阅只读状态，
/// 用户点击或既有网络恢复事件触发同一个去重恢复入口。
library;

import 'dart:async';

import 'package:get/get.dart';

import 'api_exception.dart';

class NetworkRecoveryController extends GetxService {
  final offline = false.obs;
  final retrying = false.obs;
  final hasFailures = false.obs;
  int _requestRevision = 0;
  final _latestRequests = <String, int>{};
  final _queries = <String, Future<void> Function()>{};
  final _recovered = StreamController<void>.broadcast();
  int _generation = 0;
  int get sessionGeneration => _generation;
  int _connectivityRevision = 0;
  bool _connectionFailed = false;
  bool _realtimeFailed = false;

  /// 注入现有 IM 连接与可靠同步入口，不在此层创建第二套恢复协议。
  Future<void> Function()? reconnect;
  Future<bool> Function()? _readOffline;

  /// 页面可在连接确认恢复后重新加载失败的读取任务；订阅必须随页面释放。
  Stream<void> get recovered => _recovered.stream;

  bool get visible => offline.value || hasFailures.value || retrying.value;

  String get label => retrying.value
      ? '正在重连'
      : offline.value
      ? '网络已断开'
      : '连接异常';

  /// 同一路径并发读取时仅接受最新请求结果，旧失败不能覆盖较新的成功。
  int beginQuery(String key) {
    final revision = ++_requestRevision;
    _latestRequests[key] = revision;
    return revision;
  }

  /// 同一个查询只保留一个恢复任务，不记录请求体或认证头。
  /// 保存数量受限，避免长期服务故障时持有无限量页面解码闭包。
  void queryFailed(
    String key,
    Future<void> Function() retry, {
    int? generation,
    int? revision,
  }) {
    if (isClosed ||
        (generation != null && generation != _generation) ||
        (revision != null && _latestRequests[key] != revision)) {
      return;
    }
    if (_queries.length >= 32 && !_queries.containsKey(key)) {
      final oldest = _queries.keys.first;
      _queries.remove(oldest);
      _latestRequests.remove(oldest);
    }
    _queries[key] = retry;
    hasFailures.value = true;
  }

  /// 只有相同查询成功才能移除它的失败状态，其他接口成功不能掩盖此故障。
  void querySucceeded(String key, {int? generation, int? revision}) {
    if (isClosed ||
        (generation != null && generation != _generation) ||
        (revision != null && _latestRequests[key] != revision)) {
      return;
    }
    final wasVisible = visible;
    _queries.remove(key);
    _latestRequests.remove(key);
    _publish(wasVisible);
  }

  void connectionResult(bool succeeded, {int? generation}) {
    if (isClosed || (generation != null && generation != _generation)) return;
    final wasVisible = visible;
    _connectionFailed = !succeeded;
    _publish(wasVisible);
  }

  /// 实时订阅与HTTP故障独立：接口成功不能证明WebSocket已经恢复。
  void realtimeResult(bool succeeded, {int? generation}) {
    if (isClosed || (generation != null && generation != _generation)) return;
    final wasVisible = visible;
    _realtimeFailed = !succeeded;
    _publish(wasVisible);
  }

  /// 网络接口重新可用只触发校准，不直接认定服务端已经恢复。
  void updateConnectivity(bool isOffline) {
    _connectivityRevision++;
    final wasOffline = offline.value;
    offline.value = isOffline;
    if (isOffline) _connectionFailed = true;
    hasFailures.value = _connectionFailed || _realtimeFailed || _queries.isNotEmpty;
    if (wasOffline && !isOffline) unawaited(retry(reconnectTransport: false));
  }

  /// 初始网络类型查询不能覆盖其间已经收到的新网络事件。
  Future<void> initializeConnectivity(
    Future<bool> Function() readOffline,
  ) async {
    _readOffline = readOffline;
    final revision = _connectivityRevision;
    try {
      final value = await readOffline();
      if (!isClosed && revision == _connectivityRevision) {
        updateConnectivity(value);
      }
    } catch (_) {
      // 探测能力不可用表示未知，不能误报离线。
    }
  }

  /// 手动和自动恢复共享执行锁；最多同时执行三个安全查询。
  /// 每个查询仍遵守 ApiClient 的有限重试，写入不会进入该集合。
  Future<void> retry({bool reconnectTransport = true}) async {
    if (retrying.value || isClosed) return;
    if (!reconnectTransport && !hasFailures.value) return;
    retrying.value = true;
    final generation = _generation;
    final entries = _queries.entries.toList(growable: false);
    try {
      // 已确认断网时先检查接口，避免对无网络设备批量发起必然失败的请求。
      if (offline.value && _readOffline != null) {
        await initializeConnectivity(_readOffline!);
        if (generation != _generation || offline.value) return;
      }
      for (var index = 0; index < entries.length; index += 3) {
        if (generation != _generation) return;
        await Future.wait(
          entries.skip(index).take(3).map((entry) async {
            if (!identical(_queries[entry.key], entry.value)) return;
            try {
              await entry.value();
            } catch (_) {
              // ApiClient 负责保留传输故障；不将重试异常转成 Toast。
            }
          }),
        );
      }
      if (generation != _generation) return;
      final action = reconnect;
      if (action != null && reconnectTransport) {
        await action();
        if (generation != _generation) return;
        _connectionFailed = false;
      }
    } catch (error) {
      if (generation == _generation) {
        _connectionFailed =
            error is ApiException &&
            (error.kind == ApiFailureKind.timeout ||
                error.kind == ApiFailureKind.connection ||
                const {500, 502, 503, 504}.contains(error.statusCode));
      }
    } finally {
      if (generation == _generation) {
        retrying.value = false;
        _publish(true);
      }
    }
  }

  void _publish(bool wasVisible) {
    hasFailures.value = _connectionFailed || _realtimeFailed || _queries.isNotEmpty;
    if (wasVisible && !visible && !_recovered.isClosed) _recovered.add(null);
  }

  /// 退出登录立即释放旧查询闭包并使在途恢复结果失效。
  void resetSession() {
    _generation++;
    _queries.clear();
    _latestRequests.clear();
    _connectionFailed = false;
    _realtimeFailed = false;
    retrying.value = false;
    hasFailures.value = false;
  }

  @override
  void onClose() {
    resetSession();
    reconnect = null;
    _readOffline = null;
    _recovered.close();
    super.onClose();
  }
}

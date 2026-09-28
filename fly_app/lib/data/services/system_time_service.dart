/// 系统时区与服务器时钟协调服务。
library;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/time/system_clock.dart';
import '../../domain/repositories/system_config_repository.dart';
import '../local/system_config_storage.dart';
import '../models/system_config_model.dart';

class SystemConfigRefreshResult {
  const SystemConfigRefreshResult({
    required this.success,
    this.usedDefault = false,
  });

  final bool success;
  final bool usedDefault;
}

class SystemTimeService extends GetxService with WidgetsBindingObserver {
  SystemTimeService(this._repository, this._storage);

  final SystemConfigRepository _repository;
  final SystemConfigStorage _storage;

  /// 页面读取该值建立 GetX 响应依赖；时区变化后会重新渲染全部时间文本。
  final revision = 0.obs;
  DateTime? _lastRefreshAt;
  bool _hasCachedConfig = false;
  SystemConfigModel? _currentConfig;
  Future<SystemConfigRefreshResult>? _refreshTask;

  int get uploadMaxMb =>
      _currentConfig?.uploadMaxMb ?? SystemConfigModel.defaultUploadMaxMb;

  int get uploadMaxBytes => uploadMaxMb * 1024 * 1024;

  String? get userAgreement => _currentConfig?.userAgreement;

  String? get privacyPolicyUrl => _currentConfig?.privacyPolicy;

  String? get faqUrl => _currentConfig?.faqUrl;

  String? get logoUrl => _currentConfig?.logoUrl;

  String? get appName => _currentConfig?.appName;

  bool get canRegister => _currentConfig?.openRegister == true;

  bool get registrationNeedsPhoneVerification =>
      canRegister && _currentConfig?.phoneRegisterVerification == true;

  bool get registrationNeedsEmailVerification =>
      canRegister && _currentConfig?.emailRegisterVerification == true;

  bool get registrationNeedsVerification =>
      registrationNeedsPhoneVerification || registrationNeedsEmailVerification;

  bool get registrationNeedsInvite =>
      canRegister && _currentConfig?.inviteRegister == true;

  bool get canUploadChatAttachment => _currentConfig?.openUpload == true;

  bool get canAddFriend => _currentConfig?.openAddFriend == true;

  bool canChatWith({required bool isFriend}) =>
      isFriend || _currentConfig?.privateChat == true;

  /// 未取得配置或字段无效时保持关闭，避免客户端自行启动常驻服务。
  bool get androidForegroundServiceEnabled =>
      _currentConfig?.androidForegroundServiceEnabled ?? false;

  bool isUploadTypeDenied({
    required String filename,
    required String mimeType,
  }) =>
      _currentConfig?.isUploadTypeDenied(
        filename: filename,
        mimeType: mimeType,
      ) ??
      false;

  Future<void> restoreCachedConfig() async {
    final cached = await _storage.read();
    _currentConfig = cached;
    _hasCachedConfig = cached != null;
    SystemClock.configure(
      timeZoneName: cached?.timeZoneName ?? SystemClock.defaultTimeZoneName,
    );
  }

  void startObserving() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<SystemConfigRefreshResult> refresh({bool force = false}) {
    final running = _refreshTask;
    if (running != null) return running;
    final last = _lastRefreshAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return Future.value(
        SystemConfigRefreshResult(
          success: true,
          usedDefault: !_hasCachedConfig,
        ),
      );
    }
    final task = _refresh();
    _refreshTask = task;
    task.whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
    return task;
  }

  Future<SystemConfigRefreshResult> _refresh() async {
    try {
      final config = await _repository.getPublicConfig();
      final current = _currentConfig;
      if (current != null && config.configVersion < current.configVersion) {
        _lastRefreshAt = DateTime.now();
        return const SystemConfigRefreshResult(success: true);
      }
      final validTimeZone = SystemClock.configure(
        timeZoneName: config.timeZoneName,
        serverTimeSeconds: config.serverTime,
      );
      if (!validTimeZone) {
        throw FormatException('系统配置返回未知时区：${config.timeZoneName}');
      }
      await _storage.save(config);
      _currentConfig = config;
      _hasCachedConfig = true;
      _lastRefreshAt = DateTime.now();
      revision.value++;
      return const SystemConfigRefreshResult(success: true);
    } catch (_) {
      return SystemConfigRefreshResult(
        success: false,
        usedDefault: !_hasCachedConfig,
      );
    }
  }
}

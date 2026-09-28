/// IM 协议兼容性问题上报器。
///
/// 只上报经过白名单字符清洗的短摘要，不接收原始事件、消息正文、
/// Token、URL 或附件内容，从类型边界阻止敏感数据误传。
library;

import 'package:flutter/foundation.dart';

import '../../domain/repositories/im_repository.dart';
import 'device_service.dart';

class ImProtocolIssueReporter {
  ImProtocolIssueReporter(this._repository, this._deviceService);

  static const protocolVersion = 'im-v1';
  static final RegExp _safeValuePattern = RegExp(r'[^a-zA-Z0-9_.:\-]');
  static const _allowedContextKeys = {'event_name', 'field', 'reason'};

  final ImRepository _repository;
  final DeviceService _deviceService;
  final Set<String> _acceptedIssues = <String>{};
  final Set<String> _reportingIssues = <String>{};

  /// 上报脱敏后的协议问题；上报失败不影响原业务异常。
  Future<void> report({
    required String event,
    Map<String, String> context = const {},
  }) async {
    final safeEvent = _sanitize(event, fallback: 'unknown_protocol_issue');
    final safeContext = <String, String>{};
    for (final entry in context.entries) {
      final key = _sanitize(entry.key);
      if (!_allowedContextKeys.contains(key)) continue;
      final value = _sanitize(entry.value);
      if (key.isNotEmpty && value.isNotEmpty) safeContext[key] = value;
    }
    final signature = '$safeEvent|${safeContext.entries.map((item) => '${item.key}=${item.value}').join('&')}';
    if (_acceptedIssues.contains(signature) || !_reportingIssues.add(signature)) {
      return;
    }
    try {
      await _repository.reportProtocolIssue(
        event: safeEvent,
        clientVersion: DeviceService.appVersion,
        platform: _deviceService.platform,
        protocolVersion: protocolVersion,
        context: safeContext,
      );
      _acceptedIssues.add(signature);
    } catch (error) {
      debugPrint('[IM protocol] 兼容性问题上报失败：$error');
    } finally {
      _reportingIssues.remove(signature);
    }
  }

  String _sanitize(String value, {String fallback = ''}) {
    final normalized = value.trim().replaceAll(_safeValuePattern, '_');
    if (normalized.isEmpty) return fallback;
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }
}

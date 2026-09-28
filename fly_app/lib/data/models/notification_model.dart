/// 系统通知项数据模型。
///
/// 通知列表项的数据来源,携带类型、标题、副标题、未读角标与时间文案。
library;

import '../enums/notification_kind.dart';

/// 系统通知项
class NotificationModel {
  const NotificationModel({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.badge = 0,
    this.timeText = '',
    this.notificationId = '',
    this.notificationType = 'system_announcement',
    this.actorUserId,
    this.actorUser = const {},
    this.bizType = '',
    this.bizId = '',
    this.payload = const {},
    this.actionStatus = 'none',
    this.isRead = false,
    this.readAt,
    this.createTime,
    this.updateTime,
  });

  final NotificationKind kind;
  final String title;
  final String subtitle;

  /// 未读数(0 表示无角标)
  final int badge;

  /// 时间文案(无角标时展示,如「10:30 AM」)
  final String timeText;
  final String notificationId;
  final String notificationType;
  final String? actorUserId;
  final Map<String, dynamic> actorUser;
  final String bizType;
  final String bizId;
  final Map<String, dynamic> payload;
  final String actionStatus;
  final bool isRead;
  final int? readAt;
  final int? createTime;
  final int? updateTime;

  /// 触发用户名称快照。
  ///
  /// 后端通知 payload 可能按通知类型返回 actor_user/from_user/user 等不同前缀,
  /// 前端统一做兼容读取；没有快照时回退标题，确保头像仍有稳定占位。
  String get actorName =>
      _payloadString([
        'actor_name',
        'actor_user_name',
        'from_user_name',
        'user_name',
        'nickname',
      ]) ??
      _actorUserString(['name', 'nickname', 'username']) ??
      title;

  /// 触发用户头像快照。
  String? get actorAvatarUrl =>
      _payloadString([
        'actor_avatar_url',
        'actor_user_avatar_url',
        'from_user_avatar_url',
        'user_avatar_url',
        'avatar_url',
      ]) ??
      _actorUserString(['avatar_url', 'avatar']);

  /// 好友申请发起人 ID。
  ///
  /// 好友申请通知通常在 payload.from_user_id 携带申请人 ID；部分场景只返回
  /// 顶层 actor_user_id，因此这里统一收口，供详情页和后续通知动作复用。
  String get friendRequestUserId =>
      _payloadString(['from_user_id', 'actor_user_id']) ??
      _actorUserString(['id']) ??
      actorUserId ??
      '';

  /// 申请备注。
  String get requestRemark =>
      _payloadString(['remark', 'apply_remark', 'message', 'content']) ?? '';

  /// 拒绝原因。
  String get rejectReason =>
      _payloadString(['reason', 'reject_reason', 'remark', 'message']) ?? '';

  String? _payloadString(List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  String? _actorUserString(List<String> keys) {
    for (final key in keys) {
      final value = actorUser[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    try {
      final type = json['notification_type'] as String;
      return NotificationModel(
        kind: _kind(type),
        title: json['title'] is String ? json['title'] as String : '',
        subtitle: json['content'] is String ? json['content'] as String : '',
        badge: json['is_read'] == true ? 0 : 1,
        timeText: '',
        notificationId: json['notification_id'] as String,
        notificationType: type,
        actorUserId: json['actor_user_id'] is String
            ? json['actor_user_id'] as String
            : null,
        actorUser: _payload(json['actor_user']),
        bizType: json['biz_type'] is String ? json['biz_type'] as String : '',
        bizId: json['biz_id'] is String ? json['biz_id'] as String : '',
        payload: _payload(json['payload']),
        actionStatus: json['action_status'] is String
            ? json['action_status'] as String
            : 'none',
        isRead: json['is_read'] == true,
        readAt: json['read_at'] is int ? json['read_at'] as int : null,
        createTime: json['create_time'] is int
            ? json['create_time'] as int
            : null,
        updateTime: json['update_time'] is int
            ? json['update_time'] as int
            : null,
      );
    } catch (_) {
      throw const FormatException('通知格式不正确');
    }
  }
}

NotificationKind _kind(String type) {
  if (type.startsWith('friend_')) return NotificationKind.friendRequest;
  return NotificationKind.system;
}

Map<String, dynamic> _payload(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

/// 用户详情模型(好友 / 陌生人共用)
///
/// 纯展示用:第一阶段由 Mock 直接填充。[isStranger] 决定详情页布局——
/// 好友态展示四宫格操作、完整信息卡与危险操作;陌生人态仅展示简介与
/// 「添加为联系人 / 发送消息」行动项,其余好友专属字段忽略。
class ProfileDetailModel {
  const ProfileDetailModel({
    this.id = '',
    this.publicId = '',
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.presence = '',
    this.isOnline = false,
    this.bio = '',
    this.username = '',
    this.phone = '',
    this.lastSeen = '',
    this.region = '',
    this.birthday,
    this.registerTime,
    this.isStranger = false,
    this.canAddFriend = false,
    this.hasPendingFriendRequest = false,
  });

  final String id;

  /// 公开用户 ID，用于二维码、对外搜索和分享，不使用内部自增 ID。
  final String publicId;

  /// 昵称
  final String name;

  /// 头像地址(为空时由 AppAvatar 用首字母兜底)
  final String? avatarUrl;

  /// 是否官方认证(名字旁的对勾徽标)
  final bool verified;

  /// 副标题:在线状态文案,如「最近曾上线」
  final String presence;

  /// 是否在线(头像右下角绿点)
  final bool isOnline;

  /// 个人简介
  final String bio;

  /// 用户名(含 @ 前缀)
  final String username;

  // —— 以下为好友态专属信息卡字段 ——
  final String phone;
  final String lastSeen;
  final String region;
  final DateTime? birthday;

  /// 服务端返回的秒级 Unix 时间戳。
  final int? registerTime;

  /// 是否陌生人(尚未加为好友)
  final bool isStranger;

  final bool canAddFriend;
  final bool hasPendingFriendRequest;

  factory ProfileDetailModel.fromJson(Map<String, dynamic> json) {
    try {
      final user = _jsonObject(json['user']);
      final relationship = json['relationship'] is String
          ? json['relationship'] as String
          : 'stranger';
      return ProfileDetailModel(
        id: user['id'] as String,
        publicId: user['public_id'] is String
            ? user['public_id'] as String
            : '',
        name: user['name'] as String,
        avatarUrl: user['avatar_url'] is String
            ? user['avatar_url'] as String
            : null,
        verified: user['verified'] == true,
        presence: user['presence'] is String ? user['presence'] as String : '',
        isOnline: user['is_online'] == true,
        bio: user['bio'] is String ? user['bio'] as String : '',
        username: user['username'] is String ? user['username'] as String : '',
        phone: json['phone'] is String ? json['phone'] as String : '',
        lastSeen: user['presence'] is String ? user['presence'] as String : '',
        region: json['region_code'] is String
            ? json['region_code'] as String
            : '',
        birthday: _parseBirthday(json['birthday']),
        registerTime: _parseUnixSeconds(json['register_time']),
        isStranger: relationship != 'friend' && relationship != 'self',
        canAddFriend: json['can_add_friend'] == true,
        hasPendingFriendRequest: json['has_pending_friend_request'] == true,
      );
    } catch (_) {
      throw const FormatException('用户公开资料格式不正确');
    }
  }

  static Map<String, dynamic> _jsonObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const FormatException('字段必须为 JSON 对象');
  }

  static DateTime? _parseBirthday(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String) return null;
    return DateTime.tryParse(value.trim());
  }

  static int? _parseUnixSeconds(Object? value) {
    if (value is int) return value > 0 ? value : null;
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

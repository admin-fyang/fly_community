/// 用户简要资料模型。
///
/// 联系人、搜索、群成员、通知 payload 中都会出现同一套用户快照。
class UserBriefModel {
  const UserBriefModel({
    required this.id,
    required this.publicId,
    required this.name,
    this.username,
    this.avatarUrl,
    this.verified = false,
    this.isOnline = false,
    this.presence = '',
    this.bio = '',
    this.profileVersion = 0,
  });

  final String id;
  final String publicId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final bool verified;
  final bool isOnline;
  final String presence;
  final String bio;
  final int profileVersion;

  factory UserBriefModel.fromJson(Map<String, dynamic> json) {
    try {
      if (json['id'] is! String ||
          json['public_id'] is! String ||
          json['name'] is! String) {
        throw const FormatException('用户简要资料缺少必填字段');
      }
      return UserBriefModel(
        id: json['id'] as String,
        publicId: json['public_id'] as String,
        name: json['name'] as String,
        username: json['username'] is String
            ? json['username'] as String
            : null,
        avatarUrl: json['avatar_url'] is String
            ? json['avatar_url'] as String
            : null,
        verified: json['verified'] == true,
        isOnline: json['is_online'] == true,
        presence: json['presence'] is String ? json['presence'] as String : '',
        bio: json['bio'] is String ? json['bio'] as String : '',
        profileVersion: json['profile_version'] is int
            ? json['profile_version'] as int
            : int.tryParse(json['profile_version']?.toString() ?? '') ?? 0,
      );
    } catch (_) {
      throw const FormatException('用户简要资料格式不正确');
    }
  }
}

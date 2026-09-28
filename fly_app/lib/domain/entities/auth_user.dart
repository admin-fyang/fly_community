/// 登录会话中的用户摘要。
library;

class AuthUser {
  const AuthUser({
    required this.id,
    required this.publicId,
    required this.name,
    this.avatarUrl,
    this.username,
    this.verified = false,
  });

  final String id;
  final String publicId;
  final String name;
  final String? avatarUrl;
  final String? username;
  final bool verified;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      final publicId = json['public_id'];
      final name = json['name'];
      if (id is! String || publicId is! String || name is! String) {
        throw const FormatException('用户摘要缺少必填字段');
      }
      return AuthUser(
        id: id,
        publicId: publicId,
        name: name,
        avatarUrl:
            json['avatar_url'] is String ? json['avatar_url'] as String : null,
        username:
            json['username'] is String ? json['username'] as String : null,
        verified: json['verified'] == true,
      );
    } catch (_) {
      throw const FormatException('用户摘要格式不正确');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'public_id': publicId,
    'name': name,
    'avatar_url': avatarUrl,
    'username': username,
    'verified': verified,
  };
}

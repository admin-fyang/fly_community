/// 当前登录用户的完整资料。
library;

class UserProfile {
  const UserProfile({
    required this.id,
    required this.publicId,
    required this.name,
    required this.profileVersion,
    this.firstName = '',
    this.lastName = '',
    this.avatarUrl,
    this.username,
    this.bio = '',
    this.sex = 0,
    this.birthday,
    this.regionCode,
    this.birthdayVisibility = 20,
    this.phoneVisibility = 20,
    this.lastSeenVisibility = 20,
    this.phone,
    this.phoneVerified = false,
    this.email,
    this.emailVerified = false,
    this.verified = false,
    this.status = 10,
    this.createdAt,
  });

  final String id;
  final String publicId;
  final String name;
  final String firstName;
  final String lastName;
  final String? avatarUrl;
  final String? username;
  final String bio;
  final int sex;
  final DateTime? birthday;
  final String? regionCode;
  final int birthdayVisibility;
  final int phoneVisibility;
  final int lastSeenVisibility;
  final String? phone;
  final bool phoneVerified;
  final String? email;
  final bool emailVerified;
  final bool verified;
  final int status;
  final int? createdAt;
  final int profileVersion;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    try {
      if (json['id'] is! String ||
          json['public_id'] is! String ||
          json['name'] is! String ||
          json['profile_version'] is! int) {
        throw const FormatException('用户资料缺少必填字段');
      }
      return UserProfile(
        id: json['id'] as String,
        publicId: json['public_id'] as String,
        name: json['name'] as String,
        firstName:
            json['first_name'] is String ? json['first_name'] as String : '',
        lastName:
            json['last_name'] is String ? json['last_name'] as String : '',
        avatarUrl:
            json['avatar_url'] is String ? json['avatar_url'] as String : null,
        username:
            json['username'] is String ? json['username'] as String : null,
        bio: json['bio'] is String ? json['bio'] as String : '',
        sex: json['sex'] is int ? json['sex'] as int : 0,
        birthday: _parseDate(json['birthday']),
        regionCode:
            json['region_code'] is String
                ? json['region_code'] as String
                : null,
        birthdayVisibility:
            json['birthday_visibility'] is int
                ? json['birthday_visibility'] as int
                : 20,
        phoneVisibility:
            json['phone_visibility'] is int
                ? json['phone_visibility'] as int
                : 20,
        lastSeenVisibility:
            json['last_seen_visibility'] is int
                ? json['last_seen_visibility'] as int
                : 20,
        phone: json['phone'] is String ? json['phone'] as String : null,
        phoneVerified: json['phone_verified'] == true,
        email: json['email'] is String ? json['email'] as String : null,
        emailVerified: json['email_verified'] == true,
        verified: json['verified'] == true,
        status: json['status'] is int ? json['status'] as int : 10,
        createdAt: json['created_at'] is int ? json['created_at'] as int : null,
        profileVersion: json['profile_version'] as int,
      );
    } catch (_) {
      throw const FormatException('用户资料格式不正确');
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String) throw const FormatException('birthday 格式不正确');
    return DateTime.tryParse(value);
  }
}

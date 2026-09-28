/// 用户模型（第一阶段精简版）
///
/// 字段为后续对接真实接口预留：id / avatarUrl 等。
/// avatarUrl 为空时由 UI 用 [name] 生成字母头像。
class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.fid,
    this.username,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final bool isOnline;

  /// 最近在线的文字描述，如「2小时前在线」「最近曾上线」
  final String? lastSeen;

  /// 业务展示用 ID，如 FID:123456789
  final String? fid;

  /// @用户名
  final String? username;
}

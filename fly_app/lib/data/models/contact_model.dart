/// 联系人模型
///
/// [indexKey] 为分组字母（A–Z 或 #）。第一阶段由 Mock 直接给定，
/// 避免引入拼音库；后续接真实数据时再按拼音/字母自动计算。
class ContactModel {
  const ContactModel({
    required this.id,
    required this.name,
    this.rawName,
    required this.indexKey,
    this.avatarUrl,
    this.statusText = '',
    this.isOnline = false,
    this.username,
    this.publicId = '',
    this.remark,
    this.displayName,
    this.relationship = 'friend',
    this.isPinned = false,
    this.isMuted = false,
  });

  final String id;
  final String name;

  /// 用户原始名称独立于备注展示，所有本地名称搜索均使用此值。
  final String? rawName;
  String get searchName => rawName ?? name;
  final String indexKey;
  final String? avatarUrl;
  final String statusText;
  final bool isOnline;

  /// @用户名(搜索结果 / 资料页展示);为空时由详情 Mock 兜底生成
  final String? username;

  final String publicId;
  final String? remark;
  final String? displayName;
  final String relationship;
  final bool isPinned;
  final bool isMuted;

  factory ContactModel.fromContactJson(Map<String, dynamic> json) {
    try {
      final user = _jsonObject(json['user']);
      final name = user['name'] as String? ?? '';
      final displayName = json['display_name'] is String
          ? json['display_name'] as String
          : name;
      final rawIndexKey =
          json['index_key'] ??
          json['index_letter'] ??
          user['index_key'] ??
          user['index_letter'];
      return ContactModel(
        id: user['id'] as String,
        publicId: user['public_id'] as String? ?? '',
        name: displayName,
        rawName: name,
        indexKey: _normalizeIndexKey(rawIndexKey),
        avatarUrl: user['avatar_url'] is String
            ? user['avatar_url'] as String
            : null,
        statusText: user['presence'] is String
            ? user['presence'] as String
            : '',
        isOnline: user['is_online'] == true,
        username: user['username'] is String
            ? user['username'] as String
            : null,
        remark: json['remark'] is String ? json['remark'] as String : null,
        displayName: displayName,
        relationship: json['relation_status'] is String
            ? json['relation_status'] as String
            : 'friend',
        isPinned: json['is_pinned'] == true,
        isMuted: json['is_muted'] == true,
      );
    } catch (_) {
      throw const FormatException('联系人格式不正确');
    }
  }

  factory ContactModel.fromSearchJson(Map<String, dynamic> json) {
    try {
      final user = _jsonObject(json['user']);
      return ContactModel(
        id: user['id'] as String,
        publicId: user['public_id'] as String? ?? '',
        name: user['name'] as String,
        indexKey: '#',
        avatarUrl: user['avatar_url'] is String
            ? user['avatar_url'] as String
            : null,
        statusText: user['presence'] is String
            ? user['presence'] as String
            : '',
        isOnline: user['is_online'] == true,
        username: user['username'] is String
            ? user['username'] as String
            : null,
        relationship: json['relationship'] is String
            ? json['relationship'] as String
            : 'stranger',
      );
    } catch (_) {
      throw const FormatException('搜索用户格式不正确');
    }
  }

  static Map<String, dynamic> _jsonObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw const FormatException('字段必须为 JSON 对象');
  }

  /// 服务端分组键可能为空、小写或包含多余空格，统一收敛为 A-Z/#。
  static String _normalizeIndexKey(Object? value) {
    if (value is! String) return '#';
    final key = value.trim().toUpperCase();
    if (key.length != 1) return '#';
    final codeUnit = key.codeUnitAt(0);
    return codeUnit >= 65 && codeUnit <= 90 ? key : '#';
  }
}

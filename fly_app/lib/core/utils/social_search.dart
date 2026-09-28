/// 用户与群搜索唯一解析器；名称保留大小写，显式标识非法时不回退。
library;

class SocialSearch {
  const SocialSearch(this.kind, this.value);
  final String kind;
  final String value;
  /// 社区版公开链接必须指向当前部署来源或显式指定的独立公开域名。
  static String get publicBaseUrl {
    const configured = String.fromEnvironment('PUBLIC_LINK_BASE_URL');
    if (configured.isNotEmpty) return configured;
    final current = Uri.base;
    return current.scheme == 'http' || current.scheme == 'https'
        ? current.origin
        : '';
  }

  /// 完整链接仅接受本站同源地址；路径不解码，避免非法编码绕过标识校验。
  static SocialSearch parse(String input, String type, {String? baseUrl}) {
    var value = input.trim();
    const invalid = SocialSearch('invalid', '');
    if (value.isEmpty) return invalid;
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value)) {
      final uri = Uri.tryParse(value);
      final base = Uri.tryParse(baseUrl ?? publicBaseUrl);
      if (uri == null || base == null || !['http', 'https'].contains(uri.scheme) ||
          uri.scheme != base.scheme || uri.host != base.host || uri.port != base.port ||
          RegExp(r'^[^:]+://[^/]*@').hasMatch(value) || uri.hasQuery || uri.hasFragment) {
        return invalid;
      }
      final path = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+(/.*)$').firstMatch(value)?.group(1);
      if (path == null) return invalid;
      value = path;
      if (!value.startsWith('/')) return invalid;
    }
    if (value.startsWith('/')) {
      if (!value.startsWith(type == 'user' ? '/u/' : '/g/')) return invalid;
      value = value.substring(3);
    } else if (value.startsWith('@')) {
      value = value.substring(1);
    } else {
      return SocialSearch('name', value);
    }
    final pattern = type == 'user' ? r'^[a-zA-Z][a-zA-Z0-9_]{4,31}$' : r'^[a-zA-Z0-9_]{1,64}$';
    return RegExp(pattern).hasMatch(value) ? SocialSearch('identifier', value.toLowerCase()) : invalid;
  }

  /// 空筛选返回完整本地列表；非空只对名称或指定类型的标识进行精确匹配。
  static bool matches(String input, String name, {String? identifier, String type = 'user'}) {
    if (input.trim().isEmpty) return true;
    final parsed = parse(input, type);
    if (parsed.kind == 'name') return name == parsed.value;
    if (parsed.kind != 'identifier' || identifier == null) return false;
    var id = identifier;
    if (id.startsWith('@')) id = id.substring(1);
    if (type == 'group' && id.startsWith('/g/')) id = id.substring(3);
    return id.toLowerCase() == parsed.value;
  }

  /// 链接点击必须带路径类型，@ 输入仅用于搜索，不猜测目标种类。
  static String? linkType(String input) {
    if (input.trim().startsWith('@')) return null;
    for (final type in ['user', 'group']) {
      if (parse(input, type).kind == 'identifier') return type;
    }
    return null;
  }
}

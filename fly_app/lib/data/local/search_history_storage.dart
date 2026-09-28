/// 搜索历史本地存储。
///
/// 仅持久化用户实际搜索过的关键词，不缓存搜索结果，避免本地数据与后端用户/群资料脱节。
library;

import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryStorage {
  SearchHistoryStorage({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _recentKeywordsKey = 'search.recent_keywords';
  static const maxKeywords = 10;

  final Future<SharedPreferences> _preferences;

  /// 读取最近搜索关键词。
  ///
  /// 读取时再次做裁剪与去重，防止旧版本或异常写入造成列表膨胀。
  Future<List<String>> readKeywords() async {
    final values =
        (await _preferences).getStringList(_recentKeywordsKey) ??
        const <String>[];
    final seen = <String>{};
    final keywords = <String>[];

    for (final value in values) {
      final normalized = _normalize(value);
      final key = normalized;
      if (normalized.isEmpty || !seen.add(key)) continue;
      keywords.add(normalized);
      if (keywords.length >= maxKeywords) break;
    }

    return keywords;
  }

  /// 保存搜索关键词，并返回保存后的最新列表。
  ///
  /// 同一关键词重复搜索时移动到最前面，列表只保留最近 [maxKeywords] 条。
  Future<List<String>> saveKeyword(String keyword) async {
    final normalized = _normalize(keyword);
    if (normalized.isEmpty) return readKeywords();

    final existing = await readKeywords();
    final normalizedKey = _normalizedKey(normalized);
    final next =
        <String>[
          normalized,
          ...existing.where((value) => _normalizedKey(value) != normalizedKey),
        ].take(maxKeywords).toList();

    await (await _preferences).setStringList(_recentKeywordsKey, next);
    return next;
  }

  Future<void> clear() async {
    await (await _preferences).remove(_recentKeywordsKey);
  }

  /// 名称严格匹配时，内部空白和大小写都是搜索条件的一部分，历史不能改写它们。
  static String _normalize(String value) => value.trim();

  /// 仅完全相同的输入去重；例如 Alice 与 alice 必须分别保留。
  static String _normalizedKey(String value) => _normalize(value);
}

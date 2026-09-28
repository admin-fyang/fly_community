/// 通讯录本地投影同步协议模型。
library;

enum DirectoryEntityType {
  contact,
  userBrief,
}

enum DirectoryOperation { upsert, delete }

class DirectoryChange {
  const DirectoryChange({
    required this.entityType,
    required this.entityKey,
    required this.operation,
    required this.data,
    this.revision,
  });

  final DirectoryEntityType entityType;
  final String entityKey;
  final DirectoryOperation operation;
  final Map<String, dynamic> data;
  final String? revision;

  bool get isDelete => operation == DirectoryOperation.delete;

  factory DirectoryChange.fromJson(Map<String, dynamic> json) {
    final type = switch (json['entity_type']?.toString()) {
      'contact' => DirectoryEntityType.contact,
      'user_brief' => DirectoryEntityType.userBrief,
      _ => throw const FormatException('未知目录实体类型'),
    };
    final key = json['entity_key']?.toString().trim() ?? '';
    if (key.isEmpty) throw const FormatException('目录实体缺少entity_key');
    final operation = json['operation']?.toString() ?? 'upsert';
    final parsedOperation = switch (operation) {
      'upsert' => DirectoryOperation.upsert,
      'delete' => DirectoryOperation.delete,
      _ => throw const FormatException('未知目录变更操作'),
    };
    final rawData = json['data'];
    final data = rawData is Map
        ? rawData.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    if (parsedOperation == DirectoryOperation.upsert && data.isEmpty) {
      throw const FormatException('目录upsert缺少完整data');
    }
    return DirectoryChange(
      entityType: type,
      entityKey: key,
      operation: parsedOperation,
      data: data,
      revision: json['revision'] == null
          ? null
          : _nonNegativeBigIntString(json['revision'], field: 'revision'),
    );
  }
}

class DirectoryBootstrapPage {
  const DirectoryBootstrapPage({
    required this.barrierEventId,
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final String barrierEventId;
  final List<DirectoryChange> items;
  final bool hasMore;
  final String? nextCursor;

  factory DirectoryBootstrapPage.fromJson(Map<String, dynamic> json) {
    final barrierEventId = _nonNegativeBigIntString(
      json['barrier_event_id'],
      field: 'barrier_event_id',
    );
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('目录快照格式不正确');
    }
    return DirectoryBootstrapPage(
      barrierEventId: barrierEventId,
      items: rawItems
          .map((item) {
            if (item is! Map) throw const FormatException('目录实体格式不正确');
            return DirectoryChange.fromJson({
              ...item.map((key, value) => MapEntry(key.toString(), value)),
              'operation': 'upsert',
            });
          })
          .toList(growable: false),
      hasMore: json['has_more'] == true,
      nextCursor: json['next_cursor'] is String
          ? json['next_cursor'] as String
          : null,
    );
  }
}

String _nonNegativeBigIntString(Object? value, {required String field}) {
  final normalized = value?.toString().trim() ?? '';
  final parsed = BigInt.tryParse(normalized);
  if (parsed == null || parsed.isNegative) {
    throw FormatException('$field必须为非负十进制字符串');
  }
  return normalized;
}

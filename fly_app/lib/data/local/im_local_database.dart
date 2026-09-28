/// IM SQLite 本地存储。
///
/// 这里保存的是客户端缓存与恢复状态，不替代服务端消息事实。
/// 所有实时事件必须在同一个 SQLite 事务中完成“业务数据写入 + event_id 去重
/// + 游标推进”，因此仅暴露事务入口给后续事件归约器使用。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../enums/conversation_type.dart';
import '../enums/message_status.dart';
import '../enums/message_type.dart';
import '../models/conversation_model.dart';
import '../models/conversation_projection_change.dart';
import '../models/contact_model.dart';
import '../models/directory_models.dart';
import '../models/im_api_models.dart';
import '../models/message_model.dart';
import 'im_pending_attachment_store.dart';
import 'im_database_platform.dart';
import 'im_local_mapper.dart';
import 'session_storage.dart';

/// 一条可恢复的本地待发送消息。
class PendingMessageRecord {
  const PendingMessageRecord({
    required this.clientMessageId,
    required this.conversationId,
    required this.payload,
    required this.retryCount,
  });

  final String clientMessageId;
  final String conversationId;
  final Map<String, dynamic> payload;
  final int retryCount;
}

/// 一条待上传附件记录；原生读取 [localPath]，Web 读取 [storedBytes]。
class PendingAttachmentRecord {
  const PendingAttachmentRecord({
    required this.clientMessageId,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    this.attachmentIndex = 0,
    this.role = 'original',
    this.localPath,
    this.storedBytes,
  });

  final String clientMessageId;
  final String filename;
  final String mimeType;
  final int fileSize;
  final int attachmentIndex;
  final String role;
  final String? localPath;
  final Object? storedBytes;
}

/// 入队事务需要写入的一项本地附件。
class PendingAttachmentWrite {
  const PendingAttachmentWrite({
    required this.attachmentIndex,
    required this.role,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.staged,
  });

  final int attachmentIndex;
  final String role;
  final String filename;
  final String mimeType;
  final int fileSize;
  final StagedPendingAttachment staged;
}

/// 某个会话成员的已读单调游标。
class ConversationReceiptRecord {
  const ConversationReceiptRecord({
    required this.conversationId,
    required this.userId,
    required this.lastReadSeq,
  });

  final String conversationId;
  final String userId;
  final int lastReadSeq;
}

/// 引用跳转时原消息在本地的可见性。
enum LocalMessageVisibility { visible, deleted, cleared }

/// 引用跳转的本地查询结果；null 表示 SQLite 中从未缓存过该消息。
class LocalMessageLookup {
  const LocalMessageLookup({required this.visibility, this.message});

  final LocalMessageVisibility visibility;
  final MessageModel? message;
}

/// 本地 IM 数据库。
///
/// [local_sync_event] 是事件幂等表；它与 [local_sync_state] 必须同事务写入，
/// 以保证至少一次投递不会造成重复消息或错误推进游标。
class ImLocalDatabase {
  ImLocalDatabase({
    required SessionStorage storage,
    ImDatabasePlatform? platform,
    ImPendingAttachmentStore? attachmentStore,
  }) : _storage = storage,
       _platform = platform ?? createImDatabasePlatform(),
       _attachmentStore = attachmentStore ?? createImPendingAttachmentStore();

  /// 社区版使用独立本地库，不读取或清除其他版本的用户数据。
  static const _databaseNamePrefix = 'flyim_community_im_user_';
  static const _databaseVersion = 1;

  final SessionStorage _storage;
  final ImDatabasePlatform _platform;
  final ImPendingAttachmentStore _attachmentStore;
  final StreamController<ConversationProjectionChange>
  _conversationChangeController =
      StreamController<ConversationProjectionChange>.broadcast(sync: true);
  final StreamController<void> _directoryChangeController =
      StreamController<void>.broadcast(sync: true);
  final Map<String, int> _conversationProjectionRevisions = {};
  Database? _database;
  String? _databaseOwnerKey;
  Future<Database>? _openingDatabase;

  Stream<ConversationProjectionChange> get conversationChanges =>
      _conversationChangeController.stream;


  /// 联系人、群资料或成员事务提交后的失效信号；订阅者收到后重新查询SQLite。
  Stream<void> get directoryChanges => _directoryChangeController.stream;


  /// HTTP 请求开始时保存各会话本地投影版本，用于阻止响应覆盖请求期间
  /// 已经提交的实时事件或本地待发送状态。
  Map<String, int> captureConversationProjectionRevisions() =>
      Map<String, int>.unmodifiable(_conversationProjectionRevisions);

  Future<Database> get database async {
    while (true) {
      final user = await _storage.readUser();
      final userId = user?.id.trim() ?? '';
      if (userId.isEmpty) {
        throw StateError('未登录时不能打开 IM 本地数据库');
      }
      final ownerKey = _databaseKey(userId);
      final opened = _database;
      if (opened != null && opened.isOpen && _databaseOwnerKey == ownerKey) {
        return opened;
      }

      final pending = _openingDatabase;
      if (pending != null) {
        await pending;
        // 等待期间账号可能已经切换，循环后必须重新读取当前用户。
        continue;
      }

      final opening = _openForOwner(ownerKey);
      _openingDatabase = opening;
      try {
        return await opening;
      } finally {
        if (identical(_openingDatabase, opening)) _openingDatabase = null;
      }
    }
  }

  Future<Database> _openForOwner(String ownerKey) async {
    final stopwatch = Stopwatch()..start();
    // 不输出用户 ID、数据库路径或消息内容，只记录初始化阶段与耗时。
    debugPrint('[IM database] Android/本地数据库初始化开始');
    final opened = _database;
    if (opened != null && opened.isOpen) await opened.close();
    _database = null;
    _databaseOwnerKey = null;

    final path = await _platform.resolveDatabasePath(
      '$_databaseNamePrefix$ownerKey.db',
    );
    debugPrint('[IM database] 开始打开账号隔离数据库');
    final result = await _platform.factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _createSchema,
      ),
    );
    _database = result;
    _databaseOwnerKey = ownerKey;
    stopwatch.stop();
    debugPrint('[IM database] 数据库初始化完成：${stopwatch.elapsedMilliseconds}ms');
    return result;
  }

  /// 用户 id 只用于生成本机数据库名；Base64Url 可避免路径分隔符和非法字符。
  String _databaseKey(String userId) =>
      base64Url.encode(utf8.encode(userId)).replaceAll('=', '');

  /// 执行 IM 事件事务。
  ///
  /// 调用方必须先将消息/会话/通知变更写入 [transaction]，再调用
  /// [markEventApplied]。未知事件不得调用该方法，游标便不会前进。
  Future<T> transaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<T> directoryTransaction<T>({
    required String expectedUserId,
    required Future<T> Function(Transaction transaction) action,
  }) async {
    final db = await _directoryDatabaseForOwner(expectedUserId);
    return db.transaction(action);
  }

  Future<Database> _directoryDatabaseForOwner(String expectedUserId) async {
    final normalized = expectedUserId.trim();
    final before = (await _storage.readUser())?.id.trim() ?? '';
    if (normalized.isEmpty || before != normalized) {
      throw StateError('目录同步账号已经变化');
    }
    final db = await database;
    final after = (await _storage.readUser())?.id.trim() ?? '';
    if (after != normalized || _databaseOwnerKey != _databaseKey(normalized)) {
      throw StateError('目录同步账号已经变化');
    }
    return db;
  }

  /// 在事件事务内按状态机单调写入通话快照。
  ///
  /// 返回 false 表示迟到事件已被终态或更高状态挡住，但调用方仍应记录
  /// event_id 并推进同步游标，避免同一迟到事件永久阻塞增量同步。
  Future<String> readSyncCursor({
    required String userId,
    required String deviceId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'local_sync_state',
      columns: const ['last_event_id'],
      where: 'user_id = ? AND device_id = ?',
      whereArgs: [userId, deviceId],
      limit: 1,
    );
    return rows.isEmpty ? '0' : rows.first['last_event_id'] as String;
  }

  /// 当前事件是否已被完整应用。
  Future<bool> isEventApplied(
    DatabaseExecutor executor, {
    required String userId,
    required String eventId,
  }) async {
    final rows = await executor.query(
      'local_sync_event',
      columns: const ['event_id'],
      where: 'user_id = ? AND event_id = ? AND is_applied = 1',
      whereArgs: [userId, eventId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 在业务数据同一事务中记录已处理事件。
  ///
  /// REST 同步游标不能在这里使用单条 event_id 推进，因为服务端返回的
  /// next_cursor 可能跨过不属于当前用户的全局事件 ID。整批完成后由
  /// [advanceSyncCursor] 保存服务端权威游标。
  Future<void> markEventApplied(
    Transaction transaction, {
    required String userId,
    required String eventId,
    required String eventType,
    required Map<String, dynamic> rawEvent,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 事件可能曾因客户端版本不支持而以 is_applied=0 保留。升级后再次处理时
    // 必须覆盖旧行并翻转为已应用，否则同步会永久重复卡在同一事件。
    await transaction.insert('local_sync_event', {
      'event_id': eventId,
      'user_id': userId,
      'event_type': eventType,
      'raw_event': jsonEncode(rawEvent),
      'is_applied': 1,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 整批同步事件全部落库后保存后端返回的权威 next_cursor。
  ///
  /// 使用单调比较防止两个并发同步请求中较旧响应覆盖较新的游标。
  Future<void> advanceSyncCursor({
    required String userId,
    required String deviceId,
    required String nextCursor,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await advanceSyncCursorInTransaction(
        transaction,
        userId: userId,
        deviceId: deviceId,
        nextCursor: nextCursor,
      );
    });
  }

  /// 与当前 HTTP Sync 页的全部事件处于同一个事务，保证事件与可靠水位共进退。
  Future<void> advanceSyncCursorInTransaction(
    Transaction transaction, {
    required String userId,
    required String deviceId,
    required String nextCursor,
  }) async {
    final normalized = nextCursor.trim();
    final nextValue = BigInt.tryParse(normalized);
    if (nextValue == null || nextValue.isNegative) {
      throw const FormatException('IM next_cursor 必须为非负十进制字符串');
    }
    final rows = await transaction.query(
      'local_sync_state',
      columns: const ['last_event_id'],
      where: 'user_id = ? AND device_id = ?',
      whereArgs: [userId, deviceId],
      limit: 1,
    );
    final current =
        rows.isEmpty
            ? BigInt.zero
            : BigInt.tryParse(rows.first['last_event_id']?.toString() ?? '');
    if (current == null) {
      throw const FormatException('本地 IM 同步游标格式不正确');
    }
    if (nextValue < current) return;
    await transaction.insert('local_sync_state', {
      'user_id': userId,
      'device_id': deviceId,
      'last_event_id': normalized,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 保留未知事件原文，但不标记已应用且不推进同步游标。
  Future<void> retainUnsupportedEvent({
    required String userId,
    required String eventId,
    required String eventType,
    required Map<String, dynamic> rawEvent,
  }) async {
    final db = await database;
    await db.insert('local_sync_event', {
      'event_id': eventId,
      'user_id': userId,
      'event_type': eventType,
      'raw_event': jsonEncode(rawEvent),
      'is_applied': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 发送前持久化本地待发送载荷，应用异常退出后才能恢复重试。
  Future<void> savePendingMessage({
    required String clientMessageId,
    required String conversationId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert('local_pending_message', {
      'client_msg_id': clientMessageId,
      'conversation_id': conversationId,
      'payload': jsonEncode(payload),
      'retry_count': 0,
      'last_error': null,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 在请求服务器前原子写入本地消息、发送意图及可选附件。
  ///
  /// 页面可先展示内存气泡，但只有该事务成功后服务端请求才允许发出。
  Future<void> enqueuePendingMessage({
    required MessageModel message,
    required Map<String, dynamic> payload,
    StagedPendingAttachment? attachment,
    String? attachmentFilename,
    String? attachmentMimeType,
    int? attachmentSize,
    List<PendingAttachmentWrite> attachments = const [],
  }) async {
    final clientMessageId = message.clientMsgId?.trim() ?? '';
    final conversationId = message.conversationId?.trim() ?? '';
    if (clientMessageId.isEmpty || conversationId.isEmpty) {
      throw ArgumentError('本地待发送消息缺少 client_msg_id 或 conversation_id');
    }
    final db = await database;
    await db.transaction((transaction) async {
      await upsertMessageInTransaction(transaction, message);
      await projectConversationMessageInTransaction(transaction, message);
      await transaction.insert('local_pending_message', {
        'client_msg_id': clientMessageId,
        'conversation_id': conversationId,
        'payload': jsonEncode(payload),
        'retry_count': 0,
        'last_error': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (attachment != null) {
        await transaction.insert('local_pending_attachment', {
          'client_msg_id': clientMessageId,
          'attachment_index': 0,
          'role': 'original',
          'file_name': attachmentFilename ?? '',
          'mime_type': attachmentMimeType ?? '',
          'file_size': attachmentSize ?? 0,
          'local_path': attachment.localPath,
          'file_bytes': attachment.bytes,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final item in attachments) {
        await transaction.insert('local_pending_attachment', {
          'client_msg_id': clientMessageId,
          'attachment_index': item.attachmentIndex,
          'role': item.role,
          'file_name': item.filename,
          'mime_type': item.mimeType,
          'file_size': item.fileSize,
          'local_path': item.staged.localPath,
          'file_bytes': item.staged.bytes,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await publishConversationChange(conversationId);
  }

  /// 上传完成后把发送意图替换成远端附件载荷，避免消息接口失败时重复上传。
  Future<void> updatePendingPayload(
    String clientMessageId,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    await db.update(
      'local_pending_message',
      {
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  /// 持久化用户对某个原附件的暂停选择。该状态属于待发送意图而非消息事实，
  /// 因此保存在 pending payload，应用重启后不会擅自恢复用户已暂停的上传。
  Future<void> setPendingAttachmentUploadPaused(
    String clientMessageId,
    int attachmentIndex,
    bool paused,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'local_pending_message',
        columns: const ['payload'],
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final decoded = jsonDecode(rows.first['payload']?.toString() ?? '');
      if (decoded is! Map) return;
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final rawItems = payload['items'];
      if (rawItems is! List) {
        return;
      }
      final items =
          rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    item.map((key, value) => MapEntry(key.toString(), value)),
              )
              .toList();
      for (final item in items) {
        final index = int.tryParse(item['index']?.toString() ?? '') ?? 0;
        if (index == attachmentIndex) item['upload_paused'] = paused;
      }
      payload['items'] = items;
      await transaction.update(
        'local_pending_message',
        {
          'payload': jsonEncode(payload),
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
      );
    });
  }

  Future<PendingAttachmentRecord?> readPendingAttachment(
    String clientMessageId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'local_pending_attachment',
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
      orderBy: 'attachment_index ASC, role ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PendingAttachmentRecord(
      clientMessageId: clientMessageId,
      filename: row['file_name']?.toString() ?? '',
      mimeType: row['mime_type']?.toString() ?? '',
      fileSize: int.tryParse(row['file_size']?.toString() ?? '') ?? 0,
      attachmentIndex:
          int.tryParse(row['attachment_index']?.toString() ?? '') ?? 0,
      role: row['role']?.toString() ?? 'original',
      localPath: row['local_path']?.toString(),
      storedBytes: row['file_bytes'],
    );
  }

  Future<List<PendingAttachmentRecord>> readPendingAttachments(
    String clientMessageId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'local_pending_attachment',
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
      orderBy: 'attachment_index ASC, role ASC',
    );
    return rows
        .map(
          (row) => PendingAttachmentRecord(
            clientMessageId: clientMessageId,
            filename: row['file_name']?.toString() ?? '',
            mimeType: row['mime_type']?.toString() ?? '',
            fileSize: int.tryParse(row['file_size']?.toString() ?? '') ?? 0,
            attachmentIndex:
                int.tryParse(row['attachment_index']?.toString() ?? '') ?? 0,
            role: row['role']?.toString() ?? 'original',
            localPath: row['local_path']?.toString(),
            storedBytes: row['file_bytes'],
          ),
        )
        .toList();
  }

  Future<MessageModel?> readPendingLocalMessage(String clientMessageId) async {
    final db = await database;
    final rows = await db.query(
      'local_message',
      columns: const ['payload_json'],
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
    return rows.isEmpty ? null : decodeLocalMessage(rows.first['payload_json']);
  }

  /// 为已入队的视频补写本地封面。原视频与发送意图已经存在，因此封面提取
  /// 失败不会丢掉可重试的原文件。
  Future<void> upsertPendingAttachment(
    String clientMessageId,
    PendingAttachmentWrite attachment,
  ) async {
    final db = await database;
    await db.insert('local_pending_attachment', {
      'client_msg_id': clientMessageId,
      'attachment_index': attachment.attachmentIndex,
      'role': attachment.role,
      'file_name': attachment.filename,
      'mime_type': attachment.mimeType,
      'file_size': attachment.fileSize,
      'local_path': attachment.staged.localPath,
      'file_bytes': attachment.staged.bytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 更新待发送消息的本地展示快照，例如视频封面生成完成后立即刷新气泡。
  Future<void> updatePendingLocalMessage(MessageModel message) async {
    final db = await database;
    await db.transaction((transaction) async {
      await upsertMessageInTransaction(transaction, message);
      await projectConversationMessageInTransaction(transaction, message);
    });
    final conversationId = message.conversationId?.trim() ?? '';
    if (conversationId.isNotEmpty) {
      await publishConversationChange(conversationId);
    }
  }

  Future<void> markPendingMessageFailed(
    String clientMessageId,
    String error,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.rawUpdate(
        'UPDATE local_pending_message '
        'SET retry_count = retry_count + 1, last_error = ?, updated_at = ? '
        'WHERE client_msg_id = ?',
        [error, DateTime.now().millisecondsSinceEpoch ~/ 1000, clientMessageId],
      );
      await _updatePendingStatusInExecutor(
        transaction,
        clientMessageId,
        MessageStatus.failed,
        sendError: error,
      );
    });
  }

  /// 按最早更新时间读取待发送队列，供重连和回前台时补发。
  Future<List<PendingMessageRecord>> readPendingMessages({
    int limit = 50,
  }) async {
    final db = await database;
    final rows = await db.query(
      'local_pending_message',
      orderBy: 'updated_at ASC',
      limit: limit,
    );
    final result = <PendingMessageRecord>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['payload'] as String);
        if (decoded is! Map) continue;
        result.add(
          PendingMessageRecord(
            clientMessageId: row['client_msg_id'] as String,
            conversationId: row['conversation_id'] as String,
            payload: decoded.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
            retryCount: row['retry_count'] as int,
          ),
        );
      } catch (_) {
        // 脏队列记录不能阻断其他消息恢复；保留原记录供诊断，不擅自删除用户操作。
      }
    }
    return result;
  }

  /// 读取指定待发送消息，供用户点击失败图标时精确重试。
  ///
  /// 不能调用全队列补发，否则用户点击一条消息可能意外重试
  /// 其他失败消息，也无法对当前气泡提供准确反馈。
  Future<PendingMessageRecord?> readPendingMessage(
    String clientMessageId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'local_pending_message',
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final row = rows.first;
      final decoded = jsonDecode(row['payload'] as String);
      if (decoded is! Map) return null;
      return PendingMessageRecord(
        clientMessageId: row['client_msg_id'] as String,
        conversationId: row['conversation_id'] as String,
        payload: decoded.map((key, value) => MapEntry(key.toString(), value)),
        retryCount: row['retry_count'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> removePendingMessage(String clientMessageId) async {
    final db = await database;
    await db.delete(
      'local_pending_message',
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  /// 将 HTTP 或实时事件得到的完整消息快照幂等写入 SQLite。
  Future<void> cacheMessages(Iterable<MessageModel> messages) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final message in messages) {
        await upsertMessageInTransaction(transaction, message);
      }
    });
  }

  /// 消息和会话预览在同一事务中落库。
  Future<void> upsertMessageInTransaction(
    DatabaseExecutor executor,
    MessageModel message,
  ) async {
    final conversationId = message.conversationId?.trim() ?? '';
    final clientMessageId = message.clientMsgId?.trim() ?? '';
    if (message.id.isEmpty || conversationId.isEmpty) return;
    final serverConfirmed = message.seq != null && message.seq! > 0;
    final messageId = serverConfirmed ? message.id : null;
    final matches = <Map<String, Object?>>[];
    if (clientMessageId.isNotEmpty) {
      matches.addAll(
        await executor.query(
          'local_message',
          columns: const ['local_id'],
          where: 'client_msg_id = ?',
          whereArgs: [clientMessageId],
          limit: 1,
        ),
      );
    }
    if (messageId != null) {
      final byMessageId = await executor.query(
        'local_message',
        columns: const ['local_id'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      for (final row in byMessageId) {
        if (matches.every(
          (existing) => existing['local_id'] != row['local_id'],
        )) {
          matches.add(row);
        }
      }
    }
    final localId =
        matches.isNotEmpty
            ? matches.first['local_id'].toString()
            : clientMessageId.isNotEmpty
            ? clientMessageId
            : 'remote:${message.id}';
    // 历史异常或竞态可能留下两行；保留最早命中的稳定 local_id，删除其余重复行。
    for (final duplicate in matches.skip(1)) {
      await executor.delete(
        'local_message',
        where: 'local_id = ?',
        whereArgs: [duplicate['local_id']],
      );
    }
    final values = <String, Object?>{
      'local_id': localId,
      'message_id': messageId,
      'conversation_id': conversationId,
      'seq': message.seq?.toString(),
      'client_msg_id': clientMessageId.isEmpty ? null : clientMessageId,
      'sender_id': message.senderId,
      'message_type': message.type.name,
      'body_text': message.text,
      'status': message.type.name,
      'send_status': message.status.name,
      'reply_message_id': message.reply?.messageId,
      'visibility_state': 'visible',
      'create_time': message.time.millisecondsSinceEpoch ~/ 1000,
      'payload_json': encodeLocalMessage(message),
    };
    if (matches.isEmpty) {
      await executor.insert('local_message', values);
    } else {
      values.remove('local_id');
      await executor.update(
        'local_message',
        values,
        where: 'local_id = ?',
        whereArgs: [localId],
      );
    }
  }

  /// 持久化由可靠事件在客户端生成的系统消息。
  ///
  /// 这类消息没有服务端 `message_id` 和 `seq`，不能走待发送消息流程，也不能
  /// 伪装成服务端历史消息。[message.id] 必须由可靠事件的 `event_id` 派生，
  /// 从而保证 WebSocket 重投、增量同步和应用重启后的写入均保持幂等。
  Future<void> upsertLocalSystemMessage(MessageModel message) async {
    final db = await database;
    await db.transaction(
      (transaction) =>
          upsertLocalSystemMessageInTransaction(transaction, message),
    );
  }

  /// 在可靠事件事务内写入定向系统消息，保证消息投影与 event_id 去重原子提交。
  Future<void> upsertLocalSystemMessageInTransaction(
    DatabaseExecutor executor,
    MessageModel message,
  ) async {
    final conversationId = message.conversationId?.trim() ?? '';
    final messageId = message.id.trim();
    if (message.type != MessageType.system ||
        conversationId.isEmpty ||
        messageId.isEmpty) {
      throw ArgumentError('本地系统消息必须包含有效的会话 ID 和消息 ID');
    }

    final localId = 'local-system:$messageId';
    final values = <String, Object?>{
      'message_id': null,
      'conversation_id': conversationId,
      'seq': null,
      'client_msg_id': null,
      'sender_id': message.senderId,
      'message_type': MessageType.system.name,
      'body_text': message.text,
      'status': MessageType.system.name,
      'send_status': MessageStatus.sent.name,
      'reply_message_id': null,
      'visibility_state': 'visible',
      'create_time': message.time.millisecondsSinceEpoch ~/ 1000,
      'payload_json': encodeLocalMessage(
        message.copyWith(status: MessageStatus.sent),
      ),
    };
    final existing = await executor.query(
      'local_message',
      columns: const ['local_id'],
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await executor.insert('local_message', {
        'local_id': localId,
        ...values,
      });
    } else {
      await executor.update(
        'local_message',
        values,
        where: 'local_id = ?',
        whereArgs: [localId],
      );
    }
  }

  /// 将最新消息同步投影到会话列表缓存。
  ///
  /// 消息与会话摘要必须处于同一事务；否则发送完成后即使消息气泡已经存在，
  /// 返回首页仍可能看到旧摘要。较旧的补发消息不会覆盖序号更大的新消息。
  Future<void> projectConversationMessageInTransaction(
    DatabaseExecutor executor,
    MessageModel message,
  ) async {
    final conversationId = message.conversationId?.trim() ?? '';
    if (conversationId.isEmpty) return;
    final rows = await executor.query(
      'local_conversation',
      columns: const [
        'last_message_id',
        'last_seq',
        'updated_at',
        'payload_json',
      ],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final current = decodeLocalConversation(row['payload_json']);
    if (current == null) return;

    final incomingSeq = message.seq;
    final samePending =
        current.lastMessageId == message.id ||
        (message.clientMsgId?.isNotEmpty == true &&
            current.lastMessageId == message.clientMsgId);
    final isNewer =
        samePending ||
        (incomingSeq != null && incomingSeq >= current.lastSeq) ||
        (incomingSeq == null && !message.time.isBefore(current.time));
    if (!isNewer) return;

    final next = current.replaceLastMessage(
      type: message.type,
      text: message.text,
      senderName: message.senderName,
      reply: message.reply,
      messageId: message.id,
      lastSeq:
          incomingSeq == null || incomingSeq < current.lastSeq
              ? current.lastSeq
              : incomingSeq,
      time: message.time,
    );
    await executor.update(
      'local_conversation',
      {
        'last_message_id': message.id,
        'last_seq': next.lastSeq.toString(),
        'updated_at': message.time.millisecondsSinceEpoch ~/ 1000,
        'payload_json': encodeLocalConversation(next),
      },
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  /// 更新基础单聊待发送消息状态。
  Future<void> updatePendingMessageStatus(
    String clientMessageId,
    MessageStatus status,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await _updatePendingStatusInExecutor(
        transaction,
        clientMessageId,
        status,
        clearSendError: status == MessageStatus.sending,
      );
    });
  }

  Future<void> _updatePendingStatusInExecutor(
    DatabaseExecutor executor,
    String clientMessageId,
    MessageStatus status, {
    String? sendError,
    bool clearSendError = false,
  }) async {
    final rows = await executor.query(
      'local_message',
      columns: const ['payload_json'],
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final snapshot = decodeLocalMessage(rows.first['payload_json']);
    await executor.update(
      'local_message',
      {
        'send_status': status.name,
        if (snapshot != null)
          'payload_json': encodeLocalMessage(
            snapshot.copyWith(
              status: status,
              sendError: sendError,
              clearSendError: clearSendError,
            ),
          ),
      },
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  /// 服务端确认与待发送清理原子提交，提交后清理原生暂存文件。
  Future<void> confirmPendingMessage(
    String clientMessageId,
    MessageModel serverMessage,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await confirmPendingMessageInTransaction(
        transaction,
        clientMessageId: clientMessageId,
        serverMessage: serverMessage,
      );
    });
    final conversationId = serverMessage.conversationId?.trim() ?? '';
    if (conversationId.isNotEmpty) {
      await publishConversationChange(conversationId);
    }
  }

  /// HTTP 响应与 message_created 事件共用同一归并事务。
  Future<void> confirmPendingMessageInTransaction(
    DatabaseExecutor executor, {
    required String clientMessageId,
    required MessageModel serverMessage,
  }) async {
    final attachmentRows = await executor.query(
      'local_pending_attachment',
      columns: const ['local_path'],
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
    await upsertMessageInTransaction(
      executor,
      serverMessage.copyWith(
        clientMsgId: clientMessageId,
        status: MessageStatus.sent,
      ),
    );
    await projectConversationMessageInTransaction(
      executor,
      serverMessage.copyWith(
        clientMsgId: clientMessageId,
        status: MessageStatus.sent,
      ),
    );
    await executor.delete(
      'local_pending_message',
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
    await executor.delete(
      'local_pending_attachment',
      where: 'client_msg_id = ?',
      whereArgs: [clientMessageId],
    );
    for (final row in attachmentRows) {
      await _attachmentStore.delete(row['local_path']?.toString());
    }
  }

  /// 删除本地失败消息及其全部重试数据。
  Future<void> discardPendingMessage(String clientMessageId) async {
    final db = await database;
    final result = await db.transaction((transaction) async {
      final rows = await transaction.query(
        'local_pending_attachment',
        columns: const ['local_path'],
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
      );
      final messageRows = await transaction.query(
        'local_message',
        columns: const ['conversation_id'],
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
        limit: 1,
      );
      final conversationId =
          messageRows.isEmpty
              ? ''
              : messageRows.first['conversation_id']?.toString() ?? '';
      await transaction.delete(
        'local_pending_attachment',
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
      );
      await transaction.delete(
        'local_pending_message',
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
      );
      await transaction.delete(
        'local_message',
        where: 'client_msg_id = ?',
        whereArgs: [clientMessageId],
      );
      if (conversationId.isNotEmpty) {
        await _rebuildConversationPreviewInTransaction(
          transaction,
          conversationId,
        );
      }
      return (
        localPaths: rows.map((row) => row['local_path']?.toString()).toList(),
        conversationId: conversationId,
      );
    });
    for (final path in result.localPaths) {
      await _attachmentStore.delete(path);
    }
    if (result.conversationId.isNotEmpty) {
      await publishConversationChange(result.conversationId);
    }
  }

  /// 删除最新失败消息后，从仍可见的本地消息重建会话预览。
  Future<void> _rebuildConversationPreviewInTransaction(
    DatabaseExecutor executor,
    String conversationId,
  ) async {
    final conversationRows = await executor.query(
      'local_conversation',
      columns: const ['payload_json'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (conversationRows.isEmpty) return;
    final current = decodeLocalConversation(
      conversationRows.first['payload_json'],
    );
    if (current == null) return;
    final messageRows = await executor.query(
      'local_message',
      columns: const ['payload_json'],
      where: "conversation_id = ? AND visibility_state = 'visible'",
      whereArgs: [conversationId],
      orderBy: 'create_time DESC, CAST(seq AS INTEGER) DESC',
      limit: 1,
    );
    final latest =
        messageRows.isEmpty
            ? null
            : decodeLocalMessage(messageRows.first['payload_json']);
    final next =
        latest == null
            ? current.clearMessagePreview()
            : current.replaceLastMessage(
              type: latest.type,
              text: latest.text,
              senderName: latest.senderName,
              reply: latest.reply,
              messageId: latest.id,
              lastSeq:
                  latest.seq == null || latest.seq! < current.lastSeq
                      ? current.lastSeq
                      : latest.seq!,
              time: latest.time,
            );
    await executor.update(
      'local_conversation',
      {
        'last_message_id': next.lastMessageId,
        'last_seq': next.lastSeq.toString(),
        'unread_count': next.unreadCount,
        'updated_at': next.time.millisecondsSinceEpoch ~/ 1000,
        'payload_json': encodeLocalConversation(next),
      },
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<List<MessageModel>> readCachedMessages({
    required String conversationId,
    required String currentUserId,
    int limit = 30,
    String? beforeSeq,
  }) async {
    final db = await database;
    final rows = await db.query(
      'local_message',
      where:
          beforeSeq == null
              ? "conversation_id = ? AND visibility_state = 'visible'"
              : "conversation_id = ? AND visibility_state = 'visible' AND CAST(seq AS INTEGER) < CAST(? AS INTEGER)",
      whereArgs:
          beforeSeq == null ? [conversationId] : [conversationId, beforeSeq],
      // 最近页统一按消息发生时间截取，不能按“是否有 seq”分区，否则本地
      // 系统消息会被挪到所有服务端消息之后。反转后得到时间升序；同秒内按
      // 系统消息、服务端消息、待发送消息排列。旧消息分页仍只命中有 seq 的消息。
      orderBy:
          'create_time DESC, '
          "CASE WHEN message_type = 'system' THEN 0 "
          'WHEN seq IS NOT NULL THEN 1 ELSE 2 END DESC, '
          'CAST(seq AS INTEGER) DESC, local_id DESC',
      limit: limit,
    );
    final messages = rows.reversed.map((row) {
      final snapshot = decodeLocalMessage(row['payload_json']);
      if (snapshot != null) return snapshot;
      final senderId = row['sender_id']?.toString();
      return MessageModel(
        id: row['message_id']?.toString() ?? row['local_id'].toString(),
        type: _localMessageType(row['message_type']?.toString()),
        conversationId: row['conversation_id'].toString(),
        clientMsgId: row['client_msg_id']?.toString(),
        seq: int.tryParse(row['seq']?.toString() ?? ''),
        isMine: senderId != null && senderId == currentUserId,
        time: DateTime.fromMillisecondsSinceEpoch(
          (int.tryParse(row['create_time']?.toString() ?? '') ?? 0) * 1000,
        ),
        senderId: senderId,
        text: row['body_text']?.toString() ?? '',
        status: _localMessageStatus(row['send_status']?.toString()),
      );
    }).toList();
    return messages;
  }

  /// 从消息缓存读取通话终态记录，不维护第二份通话历史表。
  ///
  /// SQLite 先用复合索引筛选可见通话消息；群直播属于另一种业务形态，必须在
  /// 解码完整快照后排除。分块扫描确保一页中夹杂直播记录时仍能尽量填满页面。
  Future<void> deleteCachedMessage(String messageId) async {
    final normalized = messageId.trim();
    if (normalized.isEmpty) return;
    final db = await database;
    await db.update(
      'local_message',
      {'visibility_state': 'deleted'},
      where: 'message_id = ? OR local_id = ?',
      whereArgs: [normalized, normalized],
    );
  }

  /// 物理移除从未提交到服务端的本地失败消息。
  Future<void> removeCachedMessage(String messageId) async {
    final normalized = messageId.trim();
    if (normalized.isEmpty) return;
    final db = await database;
    await db.delete(
      'local_message',
      where: 'message_id = ? OR local_id = ?',
      whereArgs: [normalized, normalized],
    );
  }

  /// 只查 SQLite，不为引用跳转发起单条消息网络请求。
  Future<LocalMessageLookup?> findCachedMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'local_message',
      columns: const ['visibility_state', 'payload_json'],
      where: 'conversation_id = ? AND message_id = ?',
      whereArgs: [conversationId, messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final visibility = switch (rows.first['visibility_state']?.toString()) {
      'deleted' => LocalMessageVisibility.deleted,
      'cleared' => LocalMessageVisibility.cleared,
      _ => LocalMessageVisibility.visible,
    };
    return LocalMessageLookup(
      visibility: visibility,
      message: decodeLocalMessage(rows.first['payload_json']),
    );
  }

  Future<void> cacheConversations(
    Iterable<ConversationModel> conversations, {
    Map<String, int>? expectedRevisions,
  }) async {
    final committed = <ConversationModel>[];
    final db = await database;
    await db.transaction((transaction) async {
      for (final conversation in conversations) {
        if (conversation.id.isEmpty) continue;
        final expectedRevision = expectedRevisions?[conversation.id] ?? 0;
        final currentRevision =
            _conversationProjectionRevisions[conversation.id] ?? 0;
        if (expectedRevisions != null && currentRevision != expectedRevision) {
          continue;
        }
        final existingRows = await transaction.query(
          'local_conversation',
          columns: const ['payload_json'],
          where: 'conversation_id = ?',
          whereArgs: [conversation.id],
          limit: 1,
        );
        final existing =
            existingRows.isEmpty
                ? null
                : decodeLocalConversation(existingRows.first['payload_json']);
        final pendingRows = await transaction.query(
          'local_pending_message',
          columns: const ['client_msg_id'],
          where: 'conversation_id = ?',
          whereArgs: [conversation.id],
        );
        final pendingIds =
            pendingRows
                .map((row) => row['client_msg_id']?.toString())
                .whereType<String>()
                .toSet();
        final keepLocalPreview =
            existing != null &&
            (existing.lastSeq > conversation.lastSeq ||
                pendingIds.contains(existing.lastMessageId));
        final snapshot =
            keepLocalPreview
                ? ConversationModel(
                  id: conversation.id,
                  type: conversation.type,
                  title: conversation.title,
                  peerUserId: conversation.peerUserId,
                  avatarUrl: conversation.avatarUrl,
                  lastMessageType: existing.lastMessageType,
                  lastMessageText: existing.lastMessageText,
                  lastSenderName: existing.lastSenderName,
                  lastReply: existing.lastReply,
                  lastMessageId: existing.lastMessageId,
                  lastSeq: existing.lastSeq,
                  time: existing.time,
                  unreadCount: conversation.unreadCount,
                  isPinned: conversation.isPinned,
                  isMuted: conversation.isMuted,
                )
                : conversation;
        committed.add(snapshot);
        await transaction.insert('local_conversation', {
          'conversation_id': snapshot.id,
          'type': snapshot.type.name,
          'title': snapshot.title,
          'last_message_id': snapshot.lastMessageId,
          'last_seq': snapshot.lastSeq.toString(),
          'unread_count': snapshot.unreadCount,
          'is_pinned': snapshot.isPinned ? 1 : 0,
          'is_muted': snapshot.isMuted ? 1 : 0,
          'updated_at': snapshot.time.millisecondsSinceEpoch ~/ 1000,
          'payload_json': encodeLocalConversation(snapshot),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    for (final conversation in committed) {
      _conversationChangeController.add(
        ConversationProjectionChange.upsert(conversation),
      );
    }
  }

  /// 发布指定会话当前的完整 SQLite 投影。
  ///
  /// 必须在调用方事务提交之后执行；行不存在时发布删除事件。
  Future<void> publishConversationChange(String conversationId) async {
    final normalized = conversationId.trim();
    if (normalized.isEmpty) return;
    final db = await database;
    final rows = await db.query(
      'local_conversation',
      where: 'conversation_id = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      _bumpConversationProjectionRevision(normalized);
      _conversationChangeController.add(
        ConversationProjectionChange.deleted(normalized),
      );
      return;
    }
    _bumpConversationProjectionRevision(normalized);
    _conversationChangeController.add(
      ConversationProjectionChange.upsert(_conversationFromRow(rows.first)),
    );
  }

  void _bumpConversationProjectionRevision(String conversationId) {
    _conversationProjectionRevisions[conversationId] =
        (_conversationProjectionRevisions[conversationId] ?? 0) + 1;
  }

  /// 在事件事务中写入后端返回的权威会话投影。
  ///
  /// 身份、设置、未读数和服务端最后消息都以投影为准；若当前最后一条仍是
  /// 尚未确认的本地消息，则只保留它的预览，避免实时设置事件或较早的服务端
  /// 快照让发送中气泡从首页摘要中短暂消失。
  Future<void> upsertConversationProjectionInTransaction(
    DatabaseExecutor executor,
    ConversationModel projection,
  ) async {
    final rows = await executor.query(
      'local_conversation',
      columns: const ['payload_json'],
      where: 'conversation_id = ?',
      whereArgs: [projection.id],
      limit: 1,
    );
    final current =
        rows.isEmpty
            ? null
            : decodeLocalConversation(rows.first['payload_json']);
    var next = projection;
    if (current != null && await _hasPendingLastMessage(executor, current)) {
      next = ConversationModel(
        id: projection.id,
        type: projection.type,
        title: projection.title,
        peerUserId: projection.peerUserId,
        avatarUrl: projection.avatarUrl,
        lastMessageType: current.lastMessageType,
        lastMessageText: current.lastMessageText,
        lastSenderName: current.lastSenderName,
        lastReply: current.lastReply,
        lastMessageId: current.lastMessageId,
        lastSeq:
            projection.lastSeq > current.lastSeq
                ? projection.lastSeq
                : current.lastSeq,
        time: current.time,
        unreadCount: projection.unreadCount,
        isPinned: projection.isPinned,
        isMuted: projection.isMuted,
      );
    }
    await executor.insert('local_conversation', {
      'conversation_id': next.id,
      'type': next.type.name,
      'title': next.title,
      'last_message_id': next.lastMessageId,
      'last_seq': next.lastSeq.toString(),
      'unread_count': next.unreadCount,
      'is_pinned': next.isPinned ? 1 : 0,
      'is_muted': next.isMuted ? 1 : 0,
      'updated_at': next.time.millisecondsSinceEpoch ~/ 1000,
      'payload_json': encodeLocalConversation(next),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> _hasPendingLastMessage(
    DatabaseExecutor executor,
    ConversationModel conversation,
  ) async {
    final lastMessageId = conversation.lastMessageId?.trim() ?? '';
    if (lastMessageId.isEmpty) return false;
    final messageRows = await executor.query(
      'local_pending_message',
      columns: const ['client_msg_id'],
      where: 'client_msg_id = ?',
      whereArgs: [lastMessageId],
      limit: 1,
    );
    return messageRows.isNotEmpty;
  }

  /// 只更新会话列表的权威未读数，不改动最后消息、排序时间和会话设置。
  Future<void> updateConversationUnreadInTransaction(
    DatabaseExecutor executor, {
    required String conversationId,
    required int unreadCount,
  }) async {
    final rows = await executor.query(
      'local_conversation',
      columns: const ['payload_json'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = decodeLocalConversation(rows.first['payload_json']);
    if (current == null) return;
    final next = current.copyWith(
      unreadCount: unreadCount < 0 ? 0 : unreadCount,
    );
    await executor.update(
      'local_conversation',
      {
        'unread_count': next.unreadCount,
        'payload_json': encodeLocalConversation(next),
      },
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  /// 事件归约使用的会话摘要重建入口，必须由调用方现有事务承载。
  Future<void> rebuildConversationPreviewInTransaction(
    DatabaseExecutor executor,
    String conversationId,
  ) => _rebuildConversationPreviewInTransaction(executor, conversationId);

  Future<List<ConversationModel>> readCachedConversations({
    int limit = 200,
  }) async {
    final db = await database;
    final rows = await db.query(
      'local_conversation',
      orderBy: 'is_pinned DESC, updated_at DESC, conversation_id DESC',
      limit: limit,
    );
    // 搜索读取原始名称与标识，不使用用户备注或会话展示标题猜测身份。
    // 批量读取目录，避免会话列表出现逐行查询；元数据只作用于本次返回值。
    final snapshots = rows.map(_conversationFromRow).toList();
    final userIds = {for (final item in snapshots) if (item.peerUserId != null) item.peerUserId!};
    final contacts = {
      for (final row in await _searchDirectoryRows(db, 'local_contact', 'user_id', userIds))
        row['user_id'].toString(): ContactModel.fromContactJson(_decodeDirectoryPayload(row['payload_json'])),
    };
    final briefs = {
      for (final row in await _searchDirectoryRows(db, 'local_user_brief', 'user_id', userIds))
        row['user_id'].toString(): _decodeDirectoryPayload(row['payload_json']),
    };
    return rows.map((row) {
      final item = _conversationFromRow(row);
      final contact = contacts[item.peerUserId];
      final brief = briefs[item.peerUserId];
      return item.copyWith(
        searchName: brief?['name']?.toString() ?? contact?.searchName,
        searchIdentifier: brief?['username']?.toString() ?? contact?.username,
      );
    }).toList();
  }

  /// 只查询当前会话页涉及的目录项，避免每次刷新扫描全部联系人或群目录。
  Future<List<Map<String, Object?>>> _searchDirectoryRows(
    DatabaseExecutor db, String table, String key, Set<String> ids,
  ) {
    if (ids.isEmpty) return Future.value(const []);
    return db.query(table, where: '$key IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids.toList());
  }

  ConversationModel _conversationFromRow(Map<String, Object?> row) {
    final snapshot = decodeLocalConversation(row['payload_json']);
    if (snapshot != null) return snapshot;
    return ConversationModel(
      id: row['conversation_id'].toString(),
      type: _localConversationType(row['type']?.toString()),
      title: row['title']?.toString() ?? '会话',
      lastMessageType: _localMessageType(null),
      lastMessageId: row['last_message_id']?.toString(),
      lastSeq: int.tryParse(row['last_seq']?.toString() ?? '') ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch(
        (int.tryParse(row['updated_at']?.toString() ?? '') ?? 0) * 1000,
      ),
      unreadCount: int.tryParse(row['unread_count']?.toString() ?? '') ?? 0,
      isPinned: row['is_pinned'] == 1,
      isMuted: row['is_muted'] == 1,
    );
  }

  /// 清空会话的本地投影：隐藏水位前消息并清除列表预览与未读数。
  Future<void> clearConversationLocally({
    required String conversationId,
    required int clearedBeforeSeq,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await clearConversationInTransaction(
        transaction,
        conversationId: conversationId,
        clearedBeforeSeq: clearedBeforeSeq,
      );
    });
    await publishConversationChange(conversationId);
  }

  /// 批量清空已成功会话的本地投影，并在一个事务中提交全部本地变化。
  ///
  /// 批量接口只返回成功 ID，不返回各会话清空水位。此处读取本地 `last_seq`
  /// 作为当前设备已知历史的上界；后续同步事件仍会用服务端权威水位幂等覆盖。
  Future<void> clearConversationsLocally(List<String> conversationIds) async {
    if (conversationIds.isEmpty) return;
    final db = await database;
    await db.transaction((transaction) async {
      for (final conversationId in conversationIds) {
        final rows = await transaction.query(
          'local_conversation',
          columns: const ['last_seq'],
          where: 'conversation_id = ?',
          whereArgs: [conversationId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final lastSeq =
            int.tryParse(rows.first['last_seq']?.toString() ?? '') ?? 0;
        await clearConversationInTransaction(
          transaction,
          conversationId: conversationId,
          clearedBeforeSeq: lastSeq,
        );
      }
    });
    for (final conversationId in conversationIds) {
      await publishConversationChange(conversationId);
    }
  }

  /// 在事件事务内应用清空，保证业务投影与事件幂等记录原子提交。
  Future<void> clearConversationInTransaction(
    DatabaseExecutor executor, {
    required String conversationId,
    required int clearedBeforeSeq,
  }) async {
    await _discardConversationPending(executor, conversationId);
    await executor.update(
      'local_message',
      {'visibility_state': 'cleared'},
      where: 'conversation_id = ? AND CAST(seq AS INTEGER) <= ?',
      whereArgs: [conversationId, clearedBeforeSeq],
    );
    final rows = await executor.query(
      'local_conversation',
      columns: const ['payload_json'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final snapshot = decodeLocalConversation(rows.first['payload_json']);
    await executor.update(
      'local_conversation',
      {
        'last_message_id': null,
        'unread_count': 0,
        if (snapshot != null)
          'payload_json': encodeLocalConversation(
            snapshot.clearMessagePreview(),
          ),
      },
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  /// 删除当前用户会话的本地投影；旧消息保留最小可见性事实供引用判断。
  Future<void> deleteConversationLocally({
    required String conversationId,
    int? clearedBeforeSeq,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await deleteConversationInTransaction(
        transaction,
        conversationId: conversationId,
        clearedBeforeSeq: clearedBeforeSeq,
      );
    });
    await publishConversationChange(conversationId);
  }

  /// 在单个本地事务中移除批量删除成功的会话，避免首页出现半更新状态。
  Future<void> deleteConversationsLocally(List<String> conversationIds) async {
    if (conversationIds.isEmpty) return;
    final db = await database;
    await db.transaction((transaction) async {
      for (final conversationId in conversationIds) {
        await deleteConversationInTransaction(
          transaction,
          conversationId: conversationId,
        );
      }
    });
    for (final conversationId in conversationIds) {
      await publishConversationChange(conversationId);
    }
  }

  /// 在事件事务内删除会话，并隐藏删除前的所有本地历史。
  Future<void> deleteConversationInTransaction(
    DatabaseExecutor executor, {
    required String conversationId,
    int? clearedBeforeSeq,
  }) async {
    await _discardConversationPending(executor, conversationId);
    await executor.update(
      'local_message',
      {'visibility_state': 'cleared'},
      where:
          clearedBeforeSeq == null
              ? 'conversation_id = ?'
              : 'conversation_id = ? AND CAST(seq AS INTEGER) <= ?',
      whereArgs:
          clearedBeforeSeq == null
              ? [conversationId]
              : [conversationId, clearedBeforeSeq],
    );
    await executor.delete(
      'local_conversation_receipt',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    await executor.delete(
      'local_conversation',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  /// 清空或删除会话时，未发送消息不能在下次重连后“复活”。
  Future<void> _discardConversationPending(
    DatabaseExecutor executor,
    String conversationId,
  ) async {
    final attachments = await executor.rawQuery(
      'SELECT a.local_path FROM local_pending_attachment a '
      'INNER JOIN local_pending_message p '
      'ON p.client_msg_id = a.client_msg_id '
      'WHERE p.conversation_id = ?',
      [conversationId],
    );
    for (final row in attachments) {
      await _attachmentStore.delete(row['local_path']?.toString());
    }
    await executor.rawDelete(
      'DELETE FROM local_pending_attachment WHERE client_msg_id IN '
      '(SELECT client_msg_id FROM local_pending_message '
      'WHERE conversation_id = ?)',
      [conversationId],
    );
    await executor.delete(
      'local_pending_message',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    await executor.delete(
      'local_message',
      where: "conversation_id = ? AND send_status IN ('sending', 'failed')",
      whereArgs: [conversationId],
    );
  }

  /// REST 设置成功后立即更新列表，后续同步事件仍会幂等覆盖同一状态。
  Future<void> updateConversationMutedLocally({
    required String conversationId,
    required bool isMuted,
  }) async {
    await updateConversationSettingsLocally(
      conversationIds: [conversationId],
      isMuted: isMuted,
    );
  }

  /// 批量更新当前用户的会话设置，并同步行字段与完整 JSON 快照。
  ///
  /// 行字段负责 SQLite 排序/过滤，`payload_json` 负责恢复完整 UI 模型，两者必须
  /// 在同一事务更新，否则重启后可能看到置顶或静音状态回退。
  Future<void> updateConversationSettingsLocally({
    required List<String> conversationIds,
    bool? isMuted,
    bool? isPinned,
  }) async {
    if (conversationIds.isEmpty || (isMuted == null && isPinned == null)) {
      return;
    }
    final db = await database;
    await db.transaction((transaction) async {
      for (final conversationId in conversationIds) {
        final rows = await transaction.query(
          'local_conversation',
          columns: const ['payload_json'],
          where: 'conversation_id = ?',
          whereArgs: [conversationId],
          limit: 1,
        );
        final snapshot =
            rows.isEmpty
                ? null
                : decodeLocalConversation(rows.first['payload_json']);
        await transaction.update(
          'local_conversation',
          {
            if (isMuted != null) 'is_muted': isMuted ? 1 : 0,
            if (isPinned != null) 'is_pinned': isPinned ? 1 : 0,
            if (snapshot != null)
              'payload_json': encodeLocalConversation(
                snapshot.copyWith(isMuted: isMuted, isPinned: isPinned),
              ),
          },
          where: 'conversation_id = ?',
          whereArgs: [conversationId],
        );
      }
    });
    for (final conversationId in conversationIds) {
      await publishConversationChange(conversationId);
    }
  }

  /// 读取单聊对端的最新回执游标，用于恢复自己消息的状态。
  Future<ConversationReceiptRecord?> readConversationReceipt({
    required String conversationId,
    required String userId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'local_conversation_receipt',
      where: 'conversation_id = ? AND user_id = ?',
      whereArgs: [conversationId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ConversationReceiptRecord(
      conversationId: row['conversation_id'] as String,
      userId: row['user_id'] as String,
      lastReadSeq: int.tryParse(row['last_read_seq']?.toString() ?? '') ?? 0,
    );
  }

  /// 将会话/历史接口返回的 self/peer 权威快照单调写入本地库。
  Future<void> cacheConversationReadState({
    required String conversationId,
    required ImReadState readState,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await upsertConversationReadCursor(
        transaction,
        conversationId: conversationId,
        userId: readState.self.userId,
        lastReadSeq: readState.self.lastReadSeq,
      );
      final peer = readState.peer;
      if (peer != null) {
        await upsertConversationReadCursor(
          transaction,
          conversationId: conversationId,
          userId: peer.userId,
          lastReadSeq: peer.lastReadSeq,
        );
      }
    });
  }

  /// 在任意已有事务中单调推进一个成员的已读游标。
  Future<void> upsertConversationReadCursor(
    DatabaseExecutor executor, {
    required String conversationId,
    required String userId,
    required int lastReadSeq,
    int unreadCount = 0,
    int? updatedAt,
  }) async {
    final rows = await executor.query(
      'local_conversation_receipt',
      columns: const ['last_read_seq'],
      where: 'conversation_id = ? AND user_id = ?',
      whereArgs: [conversationId, userId],
      limit: 1,
    );
    final previous =
        rows.isEmpty
            ? 0
            : int.tryParse(rows.first['last_read_seq']?.toString() ?? '') ?? 0;
    final next = lastReadSeq > previous ? lastReadSeq : previous;
    await executor.insert('local_conversation_receipt', {
      'conversation_id': conversationId,
      'user_id': userId,
      'last_read_seq': next.toString(),
      'unread_count': unreadCount,
      'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 在无外部事务场景下单调保存当前账号的已读游标，并同步会话未读投影。
  ///
  /// 已读接口成功后由回执服务调用。游标推进与会话未读数必须在同一事务
  /// 提交，否则聊天页已经读完消息时，首页仍会继续展示旧角标。
  ///
  /// 当读取到会话最新 seq 时直接归零；只读取部分消息时，根据本次游标
  /// 推进量扣减当前未读数，且不会降到 0 以下。服务端后续的权威会话投影
  /// 或 receipt_updated 事件仍可覆盖这个本地即时投影。
  Future<void> saveConversationReadCursor({
    required String conversationId,
    required String userId,
    required int lastReadSeq,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final previousReceipt = await transaction.query(
        'local_conversation_receipt',
        columns: const ['last_read_seq'],
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
        limit: 1,
      );
      final previousReadSeq =
          previousReceipt.isEmpty
              ? 0
              : int.tryParse(
                    previousReceipt.first['last_read_seq']?.toString() ?? '',
                  ) ??
                  0;
      await upsertConversationReadCursor(
        transaction,
        conversationId: conversationId,
        userId: userId,
        lastReadSeq: lastReadSeq,
      );

      final conversationRows = await transaction.query(
        'local_conversation',
        columns: const ['payload_json'],
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        limit: 1,
      );
      if (conversationRows.isNotEmpty) {
        final conversation = decodeLocalConversation(
          conversationRows.first['payload_json'],
        );
        if (conversation != null) {
          final advancedBy =
              lastReadSeq > previousReadSeq ? lastReadSeq - previousReadSeq : 0;
          final unreadCount =
              lastReadSeq >= conversation.lastSeq
                  ? 0
                  : (conversation.unreadCount - advancedBy)
                      .clamp(0, conversation.unreadCount)
                      .toInt();
          await updateConversationUnreadInTransaction(
            transaction,
            conversationId: conversationId,
            unreadCount: unreadCount,
          );
        }
      }
    });
    // 事务提交后发布完整投影，让仍驻留内存的首页立即收到角标归零结果。
    await publishConversationChange(conversationId);
  }

  /// 原子缓存服务端收藏页；首次无筛选刷新时以服务端第一页作为新基线。
  Future<bool> applyDirectoryChangesInTransaction(
    DatabaseExecutor executor, {
    required Iterable<DirectoryChange> changes,
    required Object revision,
    Object snapshotRevision = '0',
  }) async {
    final normalizedRevision = _directoryRevision(revision);
    final normalizedSnapshotRevision = _directoryRevision(snapshotRevision);
    var changed = false;
    for (final change in changes) {
      final changeRevision = change.revision ?? normalizedRevision;
      if (await _applyDirectoryChange(
        executor,
        change: change,
        revision: changeRevision,
        snapshotRevision: normalizedSnapshotRevision,
      )) {
        changed = true;
      }
    }
    return changed;
  }

  /// 原子写入一页目录快照。最后一页同时清理本快照未出现的旧核心实体。
  Future<void> applyDirectorySnapshotPage(
    DirectoryBootstrapPage page, {
    String? expectedUserId,
  }) async {
    final db =
        expectedUserId == null
            ? await database
            : await _directoryDatabaseForOwner(expectedUserId);
    await db.transaction((transaction) async {
      final barrier = BigInt.parse(_directoryRevision(page.barrierEventId));
      for (final change in page.items) {
        final revision = change.revision;
        if (revision != null && BigInt.parse(revision) > barrier) {
          throw const FormatException('目录快照实体revision不能超过barrier_event_id');
        }
      }
      await applyDirectoryChangesInTransaction(
        transaction,
        changes: page.items,
        revision: page.barrierEventId,
        snapshotRevision: page.barrierEventId,
      );
      if (!page.hasMore) {
        for (final type in const [
          DirectoryEntityType.contact,
          DirectoryEntityType.userBrief,
        ]) {
          await _pruneSnapshotEntity(
            transaction,
            type: type,
            snapshotRevision: page.barrierEventId,
            barrierEventId: page.barrierEventId,
          );
        }
        await _writeDirectoryState(
          transaction,
          key: 'core_snapshot_pages_complete',
          value: page.barrierEventId,
        );
      }
    });
    _directoryChangeController.add(null);
  }

  /// 写入访问过的群成员分页快照；只有最后一页才标记完整并清理缺席成员。
  Future<void> markCoreDirectoryCalibrated({
    required Object snapshotRevision,
    required String barrierEventId,
    required String expectedUserId,
  }) async {
    final db = await _directoryDatabaseForOwner(expectedUserId);
    await db.transaction((transaction) async {
      await _writeDirectoryState(
        transaction,
        key: 'core_snapshot_complete',
        value: _directoryRevision(snapshotRevision),
      );
      await _writeDirectoryState(
        transaction,
        key: 'core_barrier_event_id',
        value: _directoryRevision(barrierEventId),
      );
    });
  }

  Future<bool> _applyDirectoryChange(
    DatabaseExecutor executor, {
    required DirectoryChange change,
    required String revision,
    required String snapshotRevision,
  }) async {
    final type = _directoryTypeName(change.entityType);
    final revisionValue = BigInt.parse(revision);
    final snapshotValue = BigInt.parse(snapshotRevision);
    final current = await executor.query(
      'local_directory_revision',
      columns: const ['last_revision'],
      where: 'entity_type = ? AND entity_key = ?',
      whereArgs: [type, change.entityKey],
      limit: 1,
    );
    final currentRevision =
        current.isEmpty
            ? BigInt.from(-1)
            : _directoryBigInt(current.first['last_revision'], fallback: -1);
    var effectiveRevision = revision;
    if (change.entityType == DirectoryEntityType.userBrief &&
        !change.isDelete) {
      final rows = await executor.query(
        'local_user_brief',
        columns: const ['profile_version'],
        where: 'user_id = ?',
        whereArgs: [change.entityKey],
        limit: 1,
      );
      final currentProfileVersion =
          rows.isEmpty ? -1 : _directoryInt(rows.first['profile_version']);
      final incomingProfileVersion = _directoryInt(
        change.data['profile_version'],
      );
      if (incomingProfileVersion <= currentProfileVersion) {
        if (revisionValue > currentRevision) {
          await executor.insert(
            'local_directory_revision',
            {
              'entity_type': type,
              'entity_key': change.entityKey,
              'last_revision': revision,
              'is_deleted': 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (snapshotValue > BigInt.zero) {
            await executor.update(
              'local_user_brief',
              {'snapshot_revision': snapshotRevision},
              where: 'user_id = ?',
              whereArgs: [change.entityKey],
            );
          }
        }
        return false;
      }
    }
    if (revisionValue <= currentRevision) {
      // 用户公开摘要另有服务端单调profile_version。个人资料更新不应为了给大型群
      // 扇出事件而制造全局event_id，因此版本更高时允许在不回退目录修订的前提下覆盖。
      if (change.entityType != DirectoryEntityType.userBrief ||
          change.isDelete) {
        return false;
      }
      effectiveRevision = currentRevision.toString();
    }

    if (change.isDelete) {
      await _deleteDirectoryEntity(
        executor,
        change.entityType,
        change.entityKey,
      );
    } else {
      await _upsertDirectoryEntity(
        executor,
        change,
        snapshotRevision: snapshotRevision,
      );
    }
    await executor.insert('local_directory_revision', {
      'entity_type': type,
      'entity_key': change.entityKey,
      'last_revision': effectiveRevision,
      'is_deleted': change.isDelete ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> _upsertDirectoryEntity(
    DatabaseExecutor executor,
    DirectoryChange change, {
    required String snapshotRevision,
  }) async {
    final data = change.data;
    final payload = jsonEncode(data);
    switch (change.entityType) {
      case DirectoryEntityType.userBrief:
        await executor.insert('local_user_brief', {
          'user_id': change.entityKey,
          'profile_version': _directoryInt(data['profile_version']),
          'payload_json': payload,
          'snapshot_revision': snapshotRevision,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      case DirectoryEntityType.contact:
        await executor.insert('local_contact', {
          'user_id': change.entityKey,
          'relation_status': data['relation_status']?.toString() ?? 'friend',
          'index_key': data['index_key']?.toString() ?? '#',
          'sort_name': data['display_name']?.toString() ?? change.entityKey,
          'is_pinned': data['is_pinned'] == true ? 1 : 0,
          'is_muted': data['is_muted'] == true ? 1 : 0,
          'updated_at': _directoryInt(data['update_time']),
          'payload_json': payload,
          'snapshot_revision': snapshotRevision,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _deleteDirectoryEntity(
    DatabaseExecutor executor,
    DirectoryEntityType type,
    String key,
  ) async {
    switch (type) {
      case DirectoryEntityType.userBrief:
        await executor.delete(
          'local_user_brief',
          where: 'user_id = ?',
          whereArgs: [key],
        );
      case DirectoryEntityType.contact:
        await executor.delete(
          'local_contact',
          where: 'user_id = ?',
          whereArgs: [key],
        );
    }
  }

  Future<void> _pruneSnapshotEntity(
    DatabaseExecutor executor, {
    required DirectoryEntityType type,
    required Object snapshotRevision,
    required Object barrierEventId,
  }) async {
    final normalizedSnapshotRevision = _directoryRevision(snapshotRevision);
    final barrierRevision = _directoryRevision(barrierEventId);
    final barrierValue = BigInt.parse(barrierRevision);
    final table = switch (type) {
      DirectoryEntityType.contact => 'local_contact',
      DirectoryEntityType.userBrief => 'local_user_brief',
    };
    final keyColumn = switch (type) {
      DirectoryEntityType.contact || DirectoryEntityType.userBrief => 'user_id',
    };
    final rows = await executor.rawQuery(
      'SELECT e.$keyColumn AS entity_key, r.last_revision FROM $table e '
      'LEFT JOIN local_directory_revision r ON r.entity_type = ? AND r.entity_key = e.$keyColumn '
      'WHERE e.snapshot_revision <> ?'
      '${type == DirectoryEntityType.userBrief ? ' AND NOT EXISTS (SELECT 1 FROM local_contact c WHERE c.user_id = e.user_id)' : ''}',
      [_directoryTypeName(type), normalizedSnapshotRevision],
    );
    for (final row in rows) {
      final key = row['entity_key']?.toString() ?? '';
      if (key.isEmpty) continue;
      if (_directoryBigInt(row['last_revision']) > barrierValue) continue;
      await _deleteDirectoryEntity(executor, type, key);
      await executor.insert('local_directory_revision', {
        'entity_type': _directoryTypeName(type),
        'entity_key': key,
        'last_revision': barrierRevision,
        'is_deleted': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _writeDirectoryState(
    DatabaseExecutor executor, {
    required String key,
    required String value,
  }) => executor.insert('local_directory_state', {
    'state_key': key,
    'state_value': value,
    'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<ContactModel>> readCachedContacts() async {
    final db = await database;
    final rows = await db.query(
      'local_contact',
      where: 'relation_status = ?',
      whereArgs: const ['friend'],
      orderBy: 'is_pinned DESC, index_key, sort_name, user_id',
    );
    return rows
        .map(
          (row) => ContactModel.fromContactJson(
            _decodeDirectoryPayload(row['payload_json']),
          ),
        )
        .toList(growable: false);
  }

  Future<int?> readDirectoryStateTime(String key) async {
    final db = await database;
    final rows = await db.query(
      'local_directory_state',
      columns: const ['updated_at'],
      where: 'state_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : int.tryParse(rows.first['updated_at']?.toString() ?? '');
  }

  Future<String?> readDirectoryStateValue(String key) async {
    final db = await database;
    final rows = await db.query(
      'local_directory_state',
      columns: const ['state_value'],
      where: 'state_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['state_value']?.toString();
  }

  Future<bool> hasDirectoryState(String key) async {
    final db = await database;
    final rows = await db.query(
      'local_directory_state',
      columns: const ['state_key'],
      where: 'state_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object>>> readCachedUserBriefVersions({
    String? expectedUserId,
  }) async {
    final db =
        expectedUserId == null
            ? await database
            : await _directoryDatabaseForOwner(expectedUserId);
    final rows = await db.query(
      'local_user_brief',
      columns: const ['user_id', 'profile_version'],
    );
    return rows
        .map(
          (row) => {
            'user_id': row['user_id']?.toString() ?? '',
            'profile_version': _directoryInt(row['profile_version']),
          },
        )
        .where((item) => (item['user_id']?.toString() ?? '').isNotEmpty)
        .toList(growable: false);
  }

  Future<void> publishDirectoryChange() async =>
      _directoryChangeController.add(null);

  /// 游标过期时清除可由服务端重建的缓存。
  ///
  /// 待发送队列刻意保留：它代表客户端尚未确认的用户操作，不能随同步缓存删除。
  Future<void> resetRebuildableCache() async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('local_conversation');
      await transaction.delete(
        'local_message',
        where: "send_status NOT IN ('sending', 'failed')",
      );
      await transaction.delete('local_notification');
      await transaction.delete('local_conversation_receipt');
      await transaction.delete('local_sync_event');
      await transaction.delete('local_sync_state');
      await transaction.delete('local_user_brief');
      await transaction.delete('local_contact');
      await transaction.delete('local_directory_revision');
      await transaction.delete('local_directory_state');
    });
  }

  Future<void> close() async {
    final opening = _openingDatabase;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // 打开失败时没有可释放的连接，继续清理本地引用。
      }
    }
    final db = _database;
    _database = null;
    _databaseOwnerKey = null;
    _conversationProjectionRevisions.clear();
    await db?.close();
  }

  Future<void> _createSchema(Database db, int version) async {
    debugPrint('[IM database] 新设备首次建表开始：version=$version');
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE local_conversation (
        conversation_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        last_message_id TEXT,
        last_seq TEXT NOT NULL DEFAULT '0',
        unread_count INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_muted INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        payload_json TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE local_message (
        local_id TEXT PRIMARY KEY,
        message_id TEXT,
        conversation_id TEXT NOT NULL,
        seq TEXT,
        client_msg_id TEXT,
        sender_id TEXT,
        message_type TEXT NOT NULL,
        body_text TEXT,
        status TEXT,
        send_status TEXT NOT NULL,
        reply_message_id TEXT,
        visibility_state TEXT NOT NULL DEFAULT 'visible',
        create_time INTEGER NOT NULL,
        payload_json TEXT,
        UNIQUE(message_id),
        UNIQUE(client_msg_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE local_notification (
        notification_id TEXT PRIMARY KEY,
        notification_type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT,
        action_status TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        create_time INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE local_conversation_receipt (
        conversation_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        last_read_seq TEXT NOT NULL DEFAULT '0',
        unread_count INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(conversation_id, user_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE local_sync_state (
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        last_event_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(user_id, device_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE local_sync_event (
        event_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        raw_event TEXT NOT NULL,
        is_applied INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        PRIMARY KEY(event_id, user_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE local_pending_message (
        client_msg_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE local_pending_attachment (
        client_msg_id TEXT NOT NULL,
        attachment_index INTEGER NOT NULL DEFAULT 0,
        role TEXT NOT NULL DEFAULT 'original',
        file_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        local_path TEXT,
        file_bytes BLOB,
        PRIMARY KEY(client_msg_id, attachment_index, role)
      )
    ''');
    _addDirectorySchema(batch);
    batch.execute(
      'CREATE INDEX idx_local_message_conversation_seq '
      'ON local_message(conversation_id, seq)',
    );
    batch.execute(
      'CREATE INDEX idx_local_message_reply '
      'ON local_message(reply_message_id)',
    );
    batch.execute(
      'CREATE INDEX idx_local_receipt_user '
      'ON local_conversation_receipt(user_id, conversation_id)',
    );
    batch.execute(
      'CREATE INDEX idx_local_event_pending '
      'ON local_sync_event(user_id, is_applied, event_id)',
    );
    await batch.commit(noResult: true);
    debugPrint('[IM database] 新设备首次建表完成');
  }

  /// 社区版用户和联系人目录投影表。
  static void _addDirectorySchema(Batch batch) {
    batch.execute('''
      CREATE TABLE local_user_brief (
        user_id TEXT PRIMARY KEY,
        profile_version INTEGER NOT NULL DEFAULT 0,
        payload_json TEXT NOT NULL,
        snapshot_revision TEXT NOT NULL DEFAULT '0'
      )
    ''');
    batch.execute('''
      CREATE TABLE local_contact (
        user_id TEXT PRIMARY KEY,
        relation_status TEXT NOT NULL,
        index_key TEXT NOT NULL DEFAULT '#',
        sort_name TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_muted INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        payload_json TEXT NOT NULL,
        snapshot_revision TEXT NOT NULL DEFAULT '0'
      )
    ''');
    batch.execute('''
      CREATE TABLE local_directory_revision (
        entity_type TEXT NOT NULL,
        entity_key TEXT NOT NULL,
        last_revision TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(entity_type, entity_key)
      )
    ''');
    batch.execute('''
      CREATE TABLE local_directory_state (
        state_key TEXT PRIMARY KEY,
        state_value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_local_contact_order ON local_contact(relation_status, is_pinned DESC, index_key, sort_name, user_id)',
    );
  }
}

MessageType _localMessageType(String? value) {
  for (final type in MessageType.values) {
    if (type.name == value) return type;
  }
  return MessageType.text;
}

MessageStatus _localMessageStatus(String? value) {
  for (final status in MessageStatus.values) {
    if (status.name == value) return status;
  }
  return MessageStatus.sent;
}

ConversationType _localConversationType(String? value) => ConversationType.single;

String _directoryTypeName(DirectoryEntityType type) => switch (type) {
  DirectoryEntityType.contact => 'contact',
  DirectoryEntityType.userBrief => 'user_brief',
};

String _directoryRevision(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  final parsed = BigInt.tryParse(normalized);
  if (parsed == null || parsed.isNegative) {
    throw const FormatException('目录修订号必须为非负十进制字符串');
  }
  return normalized;
}

BigInt _directoryBigInt(Object? value, {int fallback = 0}) =>
    BigInt.tryParse(value?.toString() ?? '') ?? BigInt.from(fallback);

int _directoryInt(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

Map<String, dynamic> _decodeDirectoryPayload(Object? value) {
  final decoded = jsonDecode(value?.toString() ?? '');
  if (decoded is! Map) throw const FormatException('本地目录投影格式损坏');
  return decoded.map((key, item) => MapEntry(key.toString(), item));
}

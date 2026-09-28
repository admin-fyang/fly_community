/// flutter_chat_ui 消息投影控制器。
///
/// SQLite 与现有聊天业务控制器仍是消息事实来源；本控制器只维护 Flyer Chat
/// 所需的有序、不可变 UI 投影，并把变化转换为细粒度 ChatOperation。
library;

import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart' as flyer;
import 'package:get/get.dart';

import '../../core/time/system_clock.dart';
import '../../core/utils/recall_message_text.dart';
import '../../data/enums/message_status.dart' as app_status;
import '../../data/enums/message_type.dart';
import '../../data/enums/conversation_type.dart';
import '../../data/local/session_storage.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../domain/entities/auth_user.dart';
import 'chat_controller.dart';
import 'chat_navigation.dart';

/// 当前阶段的 Flyer Chat 消息数据源。
///
/// 消息 ID 优先使用 client_msg_id，使本地 sending 消息被服务端确认后仍是同一个
/// 列表元素，避免通过 remove + insert 造成气泡和视口跳动。
class FlyerChatController
    with flyer.ScrollToMessageMixin
    implements flyer.ChatController {
  FlyerChatController({ChatController? chatController, SessionStorage? storage})
    : _chatController =
          chatController ??
          Get.find<ChatRouteSession>().findController<ChatController>(),
      _storage = storage ?? Get.find<SessionStorage>() {
    _domainSubscription = _chatController.messageChanges.listen(
      (messages) => _enqueueDomainSync(messages),
    );
    unawaited(_initialize());
  }

  final ChatController _chatController;
  final SessionStorage _storage;
  final StreamController<flyer.ChatOperation> _operations =
      StreamController<flyer.ChatOperation>.broadcast(sync: true);

  /// flutter_chat_ui 官方用户缓存。
  ///
  /// 在 Chat 首次构建前写入当前消息窗口的发送者，使 Username 直接走
  /// 同步缓存路径，避免先按空用户名布局、异步返回后再改变消息高度。
  final userCache = flyer.UserCache(maxSize: 100);

  final List<flyer.Message> _messages = [];
  final Map<String, MessageModel> _domainByUiId = {};
  StreamSubscription<List<MessageModel>>? _domainSubscription;
  Future<void> _syncQueue = Future<void>.value();
  bool _disposed = false;
  bool _initialProjectionCommitted = false;

  /// Chat 只有获得真实当前用户 ID 后才允许构建，否则自己的消息会左右颠倒。
  final isReady = false.obs;

  /// 每次消息投影完成后递增，供页面精确判断 SQLite/HTTP 数据是否已经转换
  /// 为 flutter_chat_ui 消息；该状态只描述数据准备，不保存或控制滚动位置。
  final projectionRevision = 0.obs;
  final currentUserId = ''.obs;
  AuthUser? _currentUser;

  ConversationModel? get conversation => _chatController.conversation;

  Future<void> _initialize() async {
    _currentUser = await _storage.readUser();
    currentUserId.value =
        _currentUser?.id ?? _chatController.currentUserId ?? 'current-user';
    await _enqueueDomainSync(_chatController.messageSnapshot);
    if (!_disposed) {
      _primeUserCache();
      isReady.value = true;
    }
  }

  /// 为 flutter_chat_ui 异步解析发送者资料。
  Future<flyer.User?> resolveUser(String userId) async => _resolveUser(userId);

  flyer.User _resolveUser(String userId) {
    final current = _currentUser;
    if (current != null && current.id == userId) {
      return flyer.User(
        id: current.id,
        name: current.name,
        imageSource: current.avatarUrl,
      );
    }
    MessageModel? domain;
    for (final message in _domainByUiId.values) {
      if (message.senderId == userId) {
        domain = message;
        break;
      }
    }
    if (domain != null) {
      return flyer.User(
        id: userId,
        name: domain.senderName ?? '用户 $userId',
        imageSource: domain.senderAvatarUrl,
      );
    }
    final conv = conversation;
    if (conv != null && conv.peerUserId == userId) {
      return flyer.User(
        id: userId,
        name: conv.title,
        imageSource: conv.avatarUrl,
      );
    }
    return flyer.User(id: userId, name: '用户 $userId');
  }

  void _primeUserCache() {
    final userIds = _messages.map((message) => message.authorId).toSet();
    for (final userId in userIds) {
      userCache.updateUser(userId, _resolveUser(userId));
    }
  }

  /// 通过 Flyer UI ID 找到完整业务消息，供长按、多选和点击行为使用。
  MessageModel? domainMessage(String uiMessageId) => _domainByUiId[uiMessageId];

  /// 头像组件需要的轻量用户展示信息。
  ///
  /// 不返回网络 ImageProvider，图片失败策略统一由项目 AppAvatar 处理。
  String displayNameForUser(String userId) {
    final current = _currentUser;
    if (current != null && current.id == userId) return current.name;
    for (final message in _domainByUiId.values) {
      if (message.senderId == userId) {
        return message.senderName?.trim().isNotEmpty == true
            ? message.senderName!
            : '用户 $userId';
      }
    }
    final conv = conversation;
    if (conv != null && conv.peerUserId == userId) return conv.title;
    return '用户 $userId';
  }

  String? avatarUrlForUser(String userId) {
    final current = _currentUser;
    if (current != null && current.id == userId) return current.avatarUrl;
    for (final message in _domainByUiId.values) {
      if (message.senderId == userId) {
        final avatarUrl = message.senderAvatarUrl?.trim();
        if (avatarUrl != null && avatarUrl.isNotEmpty) return avatarUrl;
      }
    }
    final conv = conversation;
    return conv != null && conv.peerUserId == userId ? conv.avatarUrl : null;
  }

  /// 服务端 message_id 对应的稳定 UI ID；用于点击引用后定位原消息。
  String? uiIdForDomainMessageId(String messageId) {
    for (final entry in _domainByUiId.entries) {
      if (entry.value.id == messageId) return entry.key;
    }
    return null;
  }

  /// 首屏消息已交给 Chat；后续消息变化恢复正常的细粒度动画。
  /// 此方法不读取、保存或修改任何滚动位置。
  void commitInitialProjection() => _initialProjectionCommitted = true;

  String uiIdForDomainMessage(MessageModel message) {
    final clientId = message.clientMsgId?.trim();
    if (clientId != null && clientId.isNotEmpty) return 'client:$clientId';
    return 'server:${message.id}';
  }

  /// 在引用定位等“先扩展 SQLite 分页、再立即滚动”的流程中等待 UI 投影追平。
  Future<void> synchronizeNow() =>
      _enqueueDomainSync(_chatController.messageSnapshot);

  Future<void> _enqueueDomainSync(List<MessageModel> domainMessages) {
    final snapshot = List<MessageModel>.of(domainMessages);
    _syncQueue = _syncQueue.then((_) async {
      if (_disposed) return;
      _syncFromDomain(snapshot);
    });
    return _syncQueue;
  }

  void _syncFromDomain(List<MessageModel> domainMessages) {
    final nextDomain = <String, MessageModel>{};
    final next = <flyer.Message>[];
    for (final domain in domainMessages) {
      final uiId = uiIdForDomainMessage(domain);
      nextDomain[uiId] = domain;
      next.add(_toFlyerMessage(domain, uiId));
    }

    // Chat 首次创建前，SQLite 与 HTTP 可能连续产生多个消息窗口。每次都使用
    // 无动画全量投影，使 Chat 创建时直接获得完整首屏数据。
    if (!_initialProjectionCommitted) {
      _domainByUiId
        ..clear()
        ..addAll(nextDomain);
      _messages
        ..clear()
        ..addAll(next);
      _emit(flyer.ChatOperation.set(next, animated: false));
      projectionRevision.value++;
      return;
    }

    // 只追加最新消息是最常见路径，必须使用 insert 保留当前视口和入场动画。
    if (_isPrefix(_messages, next)) {
      _domainByUiId
        ..clear()
        ..addAll(nextDomain);
      for (var index = _messages.length; index < next.length; index++) {
        final message = next[index];
        _messages.add(message);
        _emit(flyer.ChatOperation.insert(message, index));
      }
      _updateUnchangedPrefix(next);
      projectionRevision.value++;
      return;
    }

    // 历史分页只在数据头部增加消息。反向列表的底部 offset 固定为 0，
    // flutter_chat_ui 会将数据索引转换为视觉索引，历史插入不需要页面层校正位置。
    final suffixStart = next.length - _messages.length;
    if (suffixStart > 0 && _sameIds(_messages, next.skip(suffixStart))) {
      final older = next.take(suffixStart).toList();
      _domainByUiId
        ..clear()
        ..addAll(nextDomain);
      _messages.insertAll(0, older);
      _emit(flyer.ChatOperation.insertAll(older, 0));
      _updateAll(next);
      projectionRevision.value++;
      return;
    }

    if (_sameIds(_messages, next)) {
      _domainByUiId
        ..clear()
        ..addAll(nextDomain);
      _updateAll(next);
      projectionRevision.value++;
      return;
    }

    // 删除、清空或服务端窗口整体替换属于快照对账，使用无动画 set。
    // flutter_chat_ui 的有动画 set 会将差异执行为 remove + insert，
    // 会让已经在屏幕上的消息重新缩放；真正的新消息仍由 insert 保留入场动画。
    _domainByUiId
      ..clear()
      ..addAll(nextDomain);
    _messages
      ..clear()
      ..addAll(next);
    _emit(flyer.ChatOperation.set(next, animated: false));
    projectionRevision.value++;
  }

  bool _isPrefix(List<flyer.Message> current, List<flyer.Message> next) =>
      current.length <= next.length &&
      _sameIds(current, next.take(current.length));

  bool _sameIds(Iterable<flyer.Message> left, Iterable<flyer.Message> right) {
    final leftList = left.toList();
    final rightList = right.toList();
    if (leftList.length != rightList.length) return false;
    for (var i = 0; i < leftList.length; i++) {
      if (leftList[i].id != rightList[i].id) return false;
    }
    return true;
  }

  void _updateUnchangedPrefix(List<flyer.Message> next) {
    final count = _messages.length < next.length
        ? _messages.length
        : next.length;
    for (var i = 0; i < count; i++) {
      final old = _messages[i];
      final replacement = next[i];
      if (old != replacement) {
        _messages[i] = replacement;
        _emit(flyer.ChatOperation.update(old, replacement, i));
      }
    }
  }

  void _updateAll(List<flyer.Message> next) {
    for (var index = 0; index < next.length; index++) {
      final old = _messages[index];
      final replacement = next[index];
      if (old == replacement) continue;
      _messages[index] = replacement;
      _emit(flyer.ChatOperation.update(old, replacement, index));
    }
  }

  flyer.Message _toFlyerMessage(MessageModel message, String uiId) {
    final authorId =
        message.senderId ??
        (message.isMine
            ? currentUserId.value
            : conversation?.peerUserId ?? 'unknown-user');
    final metadata = <String, dynamic>{
      'domain_message_id': message.id,
      'client_msg_id': message.clientMsgId,
      'seq': message.seq,
      'message_type': message.type.name,
      'send_error': message.sendError,
      'sending': message.status == app_status.MessageStatus.sending,
      if (message.reply != null) ...{
        'reply_sender_name': message.reply!.senderName,
        'reply_summary': message.reply!.summary,
        'reply_available': message.reply!.isAvailable,
      },
    };
    final status = switch (message.status) {
      app_status.MessageStatus.sending => flyer.MessageStatus.sending,
      app_status.MessageStatus.failed => flyer.MessageStatus.error,
      app_status.MessageStatus.read => flyer.MessageStatus.seen,
      app_status.MessageStatus.sent => flyer.MessageStatus.sent,
    };
    final replyUiId = message.reply?.messageId == null
        ? null
        : uiIdForDomainMessageId(message.reply!.messageId!);
    final displayTime = SystemClock.toDisplay(message.time);

    switch (message.type) {
      case MessageType.text:
        return flyer.Message.text(
          id: uiId,
          authorId: authorId,
          replyToMessageId: replyUiId,
          createdAt: displayTime,
          status: status,
          metadata: metadata,
          text: message.text,
        );
      case MessageType.image:
        final attachment = _firstAttachment(message);
        return flyer.Message.image(
          id: uiId,
          authorId: authorId,
          replyToMessageId: replyUiId,
          createdAt: displayTime,
          status: status,
          metadata: metadata,
          source:
              attachment?.displayUrl ??
              attachment?.localPreviewPath ??
              message.imageUrl ??
              '',
          width: attachment?.width?.toDouble(),
          height: attachment?.height?.toDouble(),
          size: attachment?.fileSize,
        );
      case MessageType.file:
        final attachment = _firstAttachment(message);
        return flyer.Message.file(
          id: uiId,
          authorId: authorId,
          replyToMessageId: replyUiId,
          createdAt: displayTime,
          status: status,
          metadata: metadata,
          source: attachment?.resourceUrl ?? '',
          name: attachment?.fileName ?? message.fileName ?? '文件',
          size: attachment?.fileSize,
          mimeType: attachment?.mimeType,
        );
        // 业务消息使用 CustomMessage 进入 flutter_chat_ui 的列表内核，
        // 非标准消息由社区版气泡统一渲染。
        return flyer.Message.custom(
          id: uiId,
          authorId: authorId,
          replyToMessageId: replyUiId,
          createdAt: displayTime,
          status: status,
          metadata: metadata,
        );
      case MessageType.recall:
      case MessageType.system:
        return flyer.Message.system(
          id: uiId,
          authorId: authorId,
          createdAt: displayTime,
          status: status,
          metadata: metadata,
          text: _summary(message),
        );
    }
  }

  MessageAttachment? _firstAttachment(MessageModel message) =>
      message.attachments.isEmpty ? null : message.attachments.first;

  String _summary(MessageModel message) => switch (message.type) {
    MessageType.image =>
      message.attachments.length > 1
          ? '[图片 ×${message.attachments.length}]'
          : '[图片]',
    MessageType.file =>
      message.fileName?.trim().isNotEmpty == true
          ? '[文件] ${message.fileName}'
          : '[文件]',
    MessageType.recall => recallMessageText(isMine: message.isMine),
    MessageType.system => message.text,
    MessageType.text => message.text,
  };

  void _emit(flyer.ChatOperation operation) {
    if (!_disposed && !_operations.isClosed) _operations.add(operation);
  }

  @override
  List<flyer.Message> get messages =>
      List<flyer.Message>.unmodifiable(_messages);

  @override
  Stream<flyer.ChatOperation> get operationsStream => _operations.stream;

  @override
  Future<void> insertMessage(flyer.Message message, {int? index}) async {
    final target = (index ?? _messages.length).clamp(0, _messages.length);
    _messages.insert(target, message);
    _emit(flyer.ChatOperation.insert(message, target));
  }

  @override
  Future<void> insertAllMessages(
    List<flyer.Message> messages, {
    int? index,
  }) async {
    final target = (index ?? _messages.length).clamp(0, _messages.length);
    _messages.insertAll(target, messages);
    _emit(flyer.ChatOperation.insertAll(messages, target));
  }

  @override
  Future<void> updateMessage(
    flyer.Message oldMessage,
    flyer.Message newMessage,
  ) async {
    final index = _messages.indexWhere((item) => item.id == oldMessage.id);
    if (index < 0) return;
    final current = _messages[index];
    _messages[index] = newMessage;
    _emit(flyer.ChatOperation.update(current, newMessage, index));
  }

  @override
  Future<void> removeMessage(flyer.Message message) async {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;
    final current = _messages.removeAt(index);
    _domainByUiId.remove(current.id);
    _emit(flyer.ChatOperation.remove(current, index));
  }

  @override
  Future<void> setMessages(List<flyer.Message> messages) async {
    _messages
      ..clear()
      ..addAll(messages);
    _emit(flyer.ChatOperation.set(messages));
  }

  /// 由聊天页释放。适配器故意不继承 GetxController：flutter_chat_ui
  /// 内部通过普通 Provider 注入 ChatController，Provider 会拒绝同时属于
  /// Listenable 的 GetxController 实例。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _domainSubscription?.cancel();
    disposeScrollMethods();
    userCache.dispose();
    unawaited(_operations.close());
  }
}

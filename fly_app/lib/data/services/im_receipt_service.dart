/// IM 已读回执协调服务。
///
/// 后端只维护成员的单调 `last_read_seq`，客户端不再制造独立的 delivered
/// 状态。同一会话短时间内产生多个可见水位时，仅上报其中最大的 seq。
library;

import '../../domain/repositories/im_repository.dart';
import '../local/im_local_database.dart';
import '../local/session_storage.dart';

class ImReceiptService {
  ImReceiptService(this._repository, this._database, this._storage);

  final ImRepository _repository;
  final ImLocalDatabase _database;
  final SessionStorage _storage;
  final Map<String, _ReadReportState> _states = {};

  /// 上报当前聊天页实际可见的最大消息序号。
  ///
  /// - 已确认过的较小水位不会重复请求；
  /// - 请求进行期间出现更大水位时，会在同一任务中继续推进；
  /// - 网络失败保留目标水位，下次页面可见或回到前台时可幂等重试。
  Future<void> reportRead({
    required String conversationId,
    required int seq,
  }) async {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty || seq <= 0) return;
    final user = await _storage.readUser();
    if (user == null) return;

    // 服务为全局单例，状态键必须包含账号，避免切换账号后沿用旧账号水位。
    final stateKey = '${user.id}\u0000$normalizedConversationId';
    final state = _states.putIfAbsent(stateKey, _ReadReportState.new);
    if (seq > state.targetSeq) state.targetSeq = seq;

    while (state.targetSeq > state.confirmedSeq) {
      final running = state.running;
      if (running != null) {
        await running;
        continue;
      }

      final task = _drain(
        normalizedConversationId,
        userId: user.id,
        state: state,
      );
      state.running = task;
      try {
        await task;
      } finally {
        if (identical(state.running, task)) state.running = null;
      }
    }

    // confirmedSeq 可能来自同一进程较早的成功请求，或来自 SQLite 中
    // 已持久化的服务端确认水位。此时无需重复调用已读接口，但仍必须确保
    // 会话列表的 unread_count 已投影到该水位。旧版本只推进了回执表，
    // 会导致接口已成功、首页角标却永久保留。
    if (state.confirmedSeq >= state.targetSeq &&
        state.projectedSeq < state.targetSeq) {
      final activeUser = await _storage.readUser();
      if (activeUser?.id != user.id) {
        throw StateError('账号已切换，终止旧账号的已读投影任务');
      }
      await _database.saveConversationReadCursor(
        conversationId: normalizedConversationId,
        userId: user.id,
        lastReadSeq: state.targetSeq,
      );
      state.projectedSeq = state.targetSeq;
    }
  }

  Future<void> _drain(
    String conversationId, {
    required String userId,
    required _ReadReportState state,
  }) async {
    final activeUser = await _storage.readUser();
    if (activeUser?.id != userId) {
      throw StateError('账号已切换，终止旧账号的已读回执任务');
    }
    final local = await _database.readConversationReceipt(
      conversationId: conversationId,
      userId: userId,
    );
    final localSeq = local?.lastReadSeq ?? 0;
    if (localSeq > state.confirmedSeq) state.confirmedSeq = localSeq;

    while (state.targetSeq > state.confirmedSeq) {
      final target = state.targetSeq;
      await _repository.markRead(conversationId: conversationId, seq: target);
      final latestUser = await _storage.readUser();
      if (latestUser?.id != userId) {
        // 网络请求期间发生账号切换时，禁止把旧账号水位写进新账号数据库。
        throw StateError('账号已切换，终止旧账号的已读回执任务');
      }
      // 只有服务端确认成功后才写入本地已确认水位，网络异常不能吞掉重试。
      await _database.saveConversationReadCursor(
        conversationId: conversationId,
        userId: userId,
        lastReadSeq: target,
      );
      state.confirmedSeq = target;
      state.projectedSeq = target;
    }
  }
}

class _ReadReportState {
  int targetSeq = 0;
  int confirmedSeq = 0;
  int projectedSeq = 0;
  Future<void>? running;
}

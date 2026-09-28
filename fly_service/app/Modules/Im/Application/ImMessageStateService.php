<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\ConversationType;
use app\enum\MessageEventType;
use app\enum\MessageStatus;
use app\exception\BusinessException;
use app\model\AppConversationMemberModel;
use app\model\AppConversationModel;
use app\model\AppFriendModel;
use app\model\AppMessageModel;
use app\model\AppMessageUserStateModel;
use app\Support\Transaction\TransactionManager;

/**
 * IM消息回执、撤回和用户可见性状态应用服务。
 */
final class ImMessageStateService
{
    private const RECALL_WINDOW_SECONDS = 120;

    /**
     * 注入事务能力和统一事件写入器。
     */
    public function __construct(
        private readonly TransactionManager $transactionManager,
        private readonly ImEventWriter $eventWriter,
    ) {
    }

    /**
     * 单调推进当前用户的会话已读游标。
     *
     * @return array<string,mixed>
     */
    public function markRead(int $userId, int $conversationId, int $seq): array
    {
        return $this->advanceReadReceipt($userId, $conversationId, $seq);
    }

    /**
     * 撤回当前用户在两分钟内发送的消息。
     *
     * @return array<string,mixed>
     */
    public function recallMessage(int $userId, int $messageId, ?string $reason): array
    {
        return $this->transactionManager->run(function () use ($userId, $messageId, $reason): array {
            $candidate = AppMessageModel::query()->whereKey($messageId)->first();
            if (!$candidate instanceof AppMessageModel) {
                throw new BusinessException('IM_MESSAGE_NOT_FOUND', '消息不存在', 404);
            }

            $conversationId = (int)$candidate->conversation_id;
            $this->lockedConversation($conversationId);
            $message = AppMessageModel::query()->whereKey($messageId)->lockForUpdate()->first();
            if (!$message instanceof AppMessageModel) {
                throw new BusinessException('IM_MESSAGE_NOT_FOUND', '消息不存在', 404);
            }
            $this->lockedMember($conversationId, $userId);

            if ((int)$message->sender_id !== $userId) {
                throw new BusinessException('IM_MESSAGE_RECALL_FORBIDDEN', '只能撤回自己发送的消息', 403);
            }

            $status = $message->status instanceof MessageStatus
                ? $message->status
                : MessageStatus::from((int)$message->status);
            if ($status === MessageStatus::Recalled) {
                $now = time();
                $this->hideReplySnapshots($conversationId, $messageId, $now);
                return $this->recallResponse($message, true);
            }
            if ($status !== MessageStatus::Normal) {
                throw new BusinessException('IM_MESSAGE_STATE_CONFLICT', '当前消息状态不允许撤回', 409);
            }

            $now = time();
            if ($now - (int)$message->create_time > self::RECALL_WINDOW_SECONDS) {
                throw new BusinessException('IM_MESSAGE_RECALL_EXPIRED', '消息已超过两分钟撤回时限', 409);
            }

            $message->status = MessageStatus::Recalled->value;
            $message->recalled_at = $now;
            $message->recalled_by = $userId;
            $message->recall_reason = $reason;
            $message->update_time = $now;
            $message->save();
            $this->hideReplySnapshots($conversationId, $messageId, $now);

            $payload = [
                'message_id' => (string)$messageId,
                'conversation_id' => (string)$conversationId,
                'seq' => (string)$message->seq,
                'message_status' => MessageStatus::Recalled->value,
                'recalled_at' => $now,
                'recalled_by' => (string)$userId,
                'recall_reason' => $reason,
            ];

            $this->writeEventsToConversationMembers(
                $conversationId,
                MessageEventType::MessageRecalled,
                $messageId,
                $payload,
                $now,
            );

            AppConversationModel::query()
                ->whereKey($conversationId)
                ->update(['update_time' => $now]);

            return $this->recallResponse($message, false);
        });
    }

    /**
     * 将所有直接引用目标消息的快照改为撤回占位。
     */
    private function hideReplySnapshots(int $conversationId, int $messageId, int $now): void
    {
        $quotedMessages = AppMessageModel::query()
            ->where('conversation_id', $conversationId)
            ->where('reply_message_id', $messageId)
            ->lockForUpdate()
            ->get();

        foreach ($quotedMessages as $quotedMessage) {
            $snapshot = is_array($quotedMessage->reply_snapshot) ? $quotedMessage->reply_snapshot : [];
            $snapshot['snapshot_version'] = 1;
            $snapshot['is_available'] = false;
            $snapshot['unavailable_reason'] = 'recalled';
            $snapshot['summary'] = '原消息已撤回';
            $snapshot['preview'] = null;
            $quotedMessage->reply_snapshot = $snapshot;
            $quotedMessage->update_time = $now;
            $quotedMessage->save();
        }
    }

    /**
     * 仅对当前用户删除指定消息。
     *
     * @return array<string,mixed>
     */
    public function deleteMessageForMe(int $userId, int $messageId): array
    {
        return $this->transactionManager->run(function () use ($userId, $messageId): array {
            $message = AppMessageModel::query()->whereKey($messageId)->first();
            if (!$message instanceof AppMessageModel) {
                throw new BusinessException('IM_MESSAGE_NOT_FOUND', '消息不存在', 404);
            }

            $conversationId = (int)$message->conversation_id;
            $member = $this->lockedMember($conversationId, $userId);
            if (!ConversationHistoryAccess::contains($member, (int)$message->seq)) {
                throw new BusinessException('IM_MESSAGE_NOT_FOUND', '消息不存在或当前不可见', 404);
            }
            $state = AppMessageUserStateModel::query()
                ->where('message_id', $messageId)
                ->where('user_id', $userId)
                ->lockForUpdate()
                ->first();

            if ($state instanceof AppMessageUserStateModel && (int)$state->is_deleted === 1) {
                return [
                    'idempotent' => true,
                    'message_id' => (string)$messageId,
                    'deleted_at' => (int)$state->deleted_at,
                ];
            }

            $now = time();
            if (!$state instanceof AppMessageUserStateModel) {
                AppMessageUserStateModel::query()->create([
                    'message_id' => $messageId,
                    'user_id' => $userId,
                    'is_deleted' => 1,
                    'deleted_at' => $now,
                    'create_time' => $now,
                    'update_time' => $now,
                ]);
            } else {
                AppMessageUserStateModel::query()
                    ->where('message_id', $messageId)
                    ->where('user_id', $userId)
                    ->update([
                        'is_deleted' => 1,
                        'deleted_at' => $now,
                        'update_time' => $now,
                    ]);
            }

            $unreadCount = $this->calculateUnreadCount($member);
            $eventId = $this->eventWriter->write(
                $userId,
                MessageEventType::MessageDeletedForMe,
                $conversationId,
                $messageId,
                [
                    'message_id' => (string)$messageId,
                    'conversation_id' => (string)$conversationId,
                    'deleted_at' => $now,
                ],
                $now,
            );

            AppConversationMemberModel::query()
                ->where('conversation_id', $conversationId)
                ->where('user_id', $userId)
                ->update([
                    'unread_count' => $unreadCount,
                    'last_event_id' => $eventId,
                    'update_time' => $now,
                ]);
            $this->advanceConversationEvent($conversationId, $eventId);

            return [
                'idempotent' => false,
                'message_id' => (string)$messageId,
                'deleted_at' => $now,
            ];
        });
    }

    /**
     * 清空当前用户在会话中的现有聊天记录。
     *
     * @param array{conversation_id:int|null,conversation_type:ConversationType|null,conversation_object_id:int|null} $locator 会话定位参数
     * @return array<string,mixed>
     */
    public function deleteConversation(int $userId, array $locator): array
    {
        return $this->transactionManager->run(function () use ($userId, $locator): array {
            $conversation = $this->lockedLocatedConversation($userId, $locator);
            if (!$conversation instanceof AppConversationModel) {
                return $this->missingConversationResponse(true);
            }

            $conversationId = (int)$conversation->conversation_id;
            $member = $this->lockedMemberOrNull($conversationId, $userId);
            $now = time();
            $settingsChanged = $this->resetPersonalConversationSettings($conversation, $userId, $now);
            if (!$member instanceof AppConversationMemberModel && !$settingsChanged) {
                return $this->missingConversationResponse(true, $conversationId);
            }

            $clearedBeforeSeq = (int)$conversation->last_seq;
            $eventId = $this->eventWriter->write(
                $userId,
                MessageEventType::ConversationUpdated,
                $conversationId,
                null,
                [
                    'reason' => 'conversation_deleted',
                    'conversation_id' => (string)$conversationId,
                    'deleted' => true,
                    'cleared_before_seq' => (string)$clearedBeforeSeq,
                    'unread_count' => 0,
                    'is_pinned' => false,
                    'is_muted' => false,
                ],
                $now,
            );
            $this->advanceConversationEvent($conversationId, $eventId);

            if ($member instanceof AppConversationMemberModel) {
                AppConversationMemberModel::query()
                    ->where('conversation_id', $conversationId)
                    ->where('user_id', $userId)
                    ->delete();
            }

            return [
                'idempotent' => false,
                'conversation_id' => (string)$conversationId,
                'deleted' => true,
                'cleared_before_seq' => (string)$clearedBeforeSeq,
                'unread_count' => 0,
                'is_pinned' => false,
                'is_muted' => false,
            ];
        });
    }

    /**
     * 批量清空当前用户的聊天记录，每个会话使用独立短事务。
     *
     * @param list<int> $conversationIds 会话ID列表
     * @return array<string,mixed>
     */
    private function advanceReadReceipt(int $userId, int $conversationId, int $seq): array
    {
        return $this->transactionManager->run(function () use ($userId, $conversationId, $seq): array {
            $conversation = $this->lockedConversation($conversationId);
            $member = $this->lockedMember($conversationId, $userId);
            if ($seq > (int)$conversation->last_seq) {
                throw new BusinessException('IM_RECEIPT_SEQ_INVALID', '回执序号超过会话最新消息', 422);
            }

            if ($seq <= (int)$member->last_read_seq) {
                return $this->receiptResponse($member, true);
            }

            if (!ConversationHistoryAccess::contains($member, $seq)) {
                throw new BusinessException('IM_RECEIPT_SEQ_INVALID', '回执序号不属于授权消息区间', 422);
            }

            $now = time();
            $previousLastReadSeq = (int)$member->last_read_seq;
            $member->last_read_seq = $seq;
            $member->unread_count = $this->calculateUnreadCount($member);
            AppConversationMemberModel::query()
                ->where('conversation_id', $conversationId)
                ->where('user_id', $userId)
                ->update([
                    'last_read_seq' => $seq,
                    'unread_count' => (int)$member->unread_count,
                    'update_time' => $now,
                ]);

            $payload = [
                'conversation_id' => (string)$conversationId,
                'user_id' => (string)$userId,
                'previous_last_read_seq' => (string)$previousLastReadSeq,
                'last_read_seq' => (string)$member->last_read_seq,
                'unread_count' => (int)$member->unread_count,
            ];
            $this->writeEventsToConversationMembers(
                $conversationId,
                MessageEventType::ReceiptUpdated,
                null,
                $payload,
                $now,
            );

            return $this->receiptResponse($member, false);
        });
    }

    /**
     * 按会话ID或会话对象ID锁定当前用户可操作的共享线程。
     *
     * @param array{conversation_id:int|null,conversation_type:ConversationType|null,conversation_object_id:int|null} $locator 会话定位参数
     */
    private function lockedLocatedConversation(int $userId, array $locator): ?AppConversationModel
    {
        $query = AppConversationModel::query();
        if ($locator['conversation_id'] !== null) {
            $query->whereKey($locator['conversation_id']);
        } elseif ($locator['conversation_type'] === ConversationType::Single) {
            $targetUserId = (int)$locator['conversation_object_id'];
            if ($targetUserId === $userId) {
                return null;
            }
            $query->where('chat_key', 'single:' . min($userId, $targetUserId) . ':' . max($userId, $targetUserId));
        } else {
            return null;
        }

        $conversation = $query
            ->where('conversation_type', ConversationType::Single->value)
            ->lockForUpdate()
            ->first();
        if (!$conversation instanceof AppConversationModel) {
            return null;
        }

        $hasMemberRecord = AppConversationMemberModel::query()
            ->where('conversation_id', (int)$conversation->conversation_id)
            ->where('user_id', $userId)
            ->exists();
        if ($hasMemberRecord || $this->isUnderlyingConversationParticipant($conversation, $userId)) {
            return $conversation;
        }

        return null;
    }

    /** 判断用户是否属于单聊共享线程。 */
    private function isUnderlyingConversationParticipant(AppConversationModel $conversation, int $userId): bool
    {
        $type = $conversation->conversation_type instanceof ConversationType
            ? $conversation->conversation_type
            : ConversationType::from((int)$conversation->conversation_type);
        return $type === ConversationType::Single
            && in_array($userId, $this->singleParticipantUserIds((string)$conversation->chat_key), true);
    }

    /**
     * 从单聊业务键解析双方用户ID。
     *
     * @return list<int>
     */
    private function singleParticipantUserIds(string $chatKey): array
    {
        if (preg_match('/^single:([1-9][0-9]*):([1-9][0-9]*)$/', $chatKey, $matches) !== 1) {
            return [];
        }

        return [(int)$matches[1], (int)$matches[2]];
    }

    /**
     * 锁定当前用户会话记录；记录已被删除时返回空。
     */
    private function lockedMemberOrNull(int $conversationId, int $userId): ?AppConversationMemberModel
    {
        $member = AppConversationMemberModel::query()
            ->where('conversation_id', $conversationId)
            ->where('user_id', $userId)
            ->lockForUpdate()
            ->first();

        return $member instanceof AppConversationMemberModel ? $member : null;
    }

    /** 删除单聊会话时同步重置联系人的个人会话设置。 */
    private function resetPersonalConversationSettings(
        AppConversationModel $conversation,
        int $userId,
        int $now,
    ): bool {
        $type = $conversation->conversation_type instanceof ConversationType
            ? $conversation->conversation_type
            : ConversationType::from((int)$conversation->conversation_type);
        if ($type === ConversationType::Single) {
            $participantIds = $this->singleParticipantUserIds((string)$conversation->chat_key);
            $peerIds = array_values(array_filter(
                $participantIds,
                static fn (int $participantId): bool => $participantId !== $userId,
            ));
            if ($peerIds === []) {
                return false;
            }

            $friend = AppFriendModel::query()
                ->where('create_user', $userId)
                ->where('friend_user_id', $peerIds[0])
                ->lockForUpdate()
                ->first();
            if (!$friend instanceof AppFriendModel || ((int)$friend->is_top === 0 && (int)$friend->is_notice === 1)) {
                return false;
            }
            $friend->is_top = 0;
            $friend->is_notice = 1;
            $friend->update_time = $now;
            $friend->save();

            return true;
        }

        return false;
    }

    /**
     * 生成会话不存在或用户会话记录已删除时的幂等响应。
     *
     * @return array<string,mixed>
     */
    private function missingConversationResponse(bool $deleted, ?int $conversationId = null): array
    {
        $response = [
            'idempotent' => true,
            'conversation_id' => $conversationId === null ? null : (string)$conversationId,
            'cleared_before_seq' => null,
            'unread_count' => 0,
            'is_pinned' => false,
            'is_muted' => false,
        ];
        if ($deleted) {
            $response['deleted'] = true;
        } else {
            $response['is_hidden'] = false;
        }

        return $response;
    }

    /**
     * 锁定并读取有效会话。
     */
    private function lockedConversation(int $conversationId): AppConversationModel
    {
        $conversation = AppConversationModel::query()
            ->whereKey($conversationId)
            ->where('status', 10)
            ->lockForUpdate()
            ->first();
        if (!$conversation instanceof AppConversationModel) {
            throw new BusinessException('IM_CONVERSATION_NOT_FOUND', '会话不存在或不可用', 404);
        }

        return $conversation;
    }

    /**
     * 锁定并读取当前会话成员状态。
     */
    private function lockedMember(int $conversationId, int $userId): AppConversationMemberModel
    {
        $member = AppConversationMemberModel::query()
            ->where('conversation_id', $conversationId)
            ->where('user_id', $userId)
            ->lockForUpdate()
            ->first();
        if (!$member instanceof AppConversationMemberModel) {
            throw new BusinessException('IM_MEMBER_NOT_FOUND', '当前用户不是会话成员', 403);
        }

        return $member;
    }

    /**
     * 给当前会话所有成员写入同一业务变化的用户事件。
     *
     * @param array<string,mixed> $payload 事件载荷
     */
    private function writeEventsToConversationMembers(
        int $conversationId,
        MessageEventType $eventType,
        ?int $messageId,
        array $payload,
        int $now,
    ): void {
        $userIds = AppConversationMemberModel::query()
            ->where('conversation_id', $conversationId)
            ->pluck('user_id');
        $maxEventId = 0;

        foreach ($userIds as $eventUserId) {
            $eventId = $this->eventWriter->write(
                (int)$eventUserId,
                $eventType,
                $conversationId,
                $messageId,
                $payload,
                $now,
            );
            $maxEventId = max($maxEventId, $eventId);

            AppConversationMemberModel::query()
                ->where('conversation_id', $conversationId)
                ->where('user_id', (int)$eventUserId)
                ->update(['last_event_id' => $eventId]);
        }

        $this->advanceConversationEvent($conversationId, $maxEventId);
    }

    /**
     * 单调推进会话的全局事件位置。
     */
    private function advanceConversationEvent(int $conversationId, int $eventId): void
    {
        AppConversationModel::query()
            ->whereKey($conversationId)
            ->where('last_event_id', '<', $eventId)
            ->update(['last_event_id' => $eventId]);
    }

    /**
     * 按消息事实和用户删除状态重算未读数。
     */
    private function calculateUnreadCount(AppConversationMemberModel $member): int
    {
        $minimumSeq = max(
            (int)$member->cleared_before_seq,
            (int)$member->last_read_seq,
        );

        return AppMessageModel::query()
            ->where('conversation_id', (int)$member->conversation_id)
            ->where('seq', '>', $minimumSeq)
            ->tap(static fn ($query) => ConversationHistoryAccess::constrain($query, $member))
            ->where('sender_id', '!=', (int)$member->user_id)
            ->whereIn('status', [MessageStatus::Normal->value, MessageStatus::Recalled->value])
            ->whereNotExists(static function ($stateQuery) use ($member): void {
                $stateQuery
                    ->selectRaw('1')
                    ->from('app_message_user_state as mus')
                    ->whereColumn('mus.message_id', 'app_message.message_id')
                    ->where('mus.user_id', (int)$member->user_id)
                    ->where('mus.is_deleted', 1);
            })
            ->count();
    }

    /**
     * 生成回执接口响应。
     *
     * @return array<string,mixed>
     */
    private function receiptResponse(AppConversationMemberModel $member, bool $idempotent): array
    {
        return [
            'idempotent' => $idempotent,
            'conversation_id' => (string)$member->conversation_id,
            'last_read_seq' => (string)$member->last_read_seq,
            'unread_count' => (int)$member->unread_count,
        ];
    }

    /**
     * 生成撤回接口响应。
     *
     * @return array<string,mixed>
     */
    private function recallResponse(AppMessageModel $message, bool $idempotent): array
    {
        return [
            'idempotent' => $idempotent,
            'message_id' => (string)$message->message_id,
            'conversation_id' => (string)$message->conversation_id,
            'seq' => (string)$message->seq,
            'message_status' => MessageStatus::Recalled->value,
            'recalled_at' => $message->recalled_at === null ? null : (int)$message->recalled_at,
            'recalled_by' => $message->recalled_by === null ? null : (string)$message->recalled_by,
            'recall_reason' => $message->recall_reason,
        ];
    }
}

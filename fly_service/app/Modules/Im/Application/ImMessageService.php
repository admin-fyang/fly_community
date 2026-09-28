<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\ConversationType;
use app\enum\FriendStatus;
use app\enum\MessageEventType;
use app\enum\MessageStatus;
use app\enum\MessageType;
use app\enum\UserStatus;
use app\exception\BusinessException;
use app\model\AppConversationMemberModel;
use app\model\AppConversationModel;
use app\model\AppFileModel;
use app\model\AppFriendModel;
use app\model\AppMessageAttachmentModel;
use app\model\AppMessageModel;
use app\model\AppUserModel;
use app\Support\Transaction\TransactionManager;
use app\Modules\System\Application\SystemConfigService;
use Illuminate\Database\Capsule\Manager;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Query\JoinClause;
use Illuminate\Database\QueryException;

/**
 * IM消息与会话应用服务。
 */
final class ImMessageService
{
    /**
     * @param TransactionManager $transactionManager 事务管理器
     * @param ImEventWriter $eventWriter IM事件与Outbox写入器
     */
    public function __construct(
        private readonly TransactionManager $transactionManager,
        private readonly ImEventWriter $eventWriter,
        private readonly ?SystemConfigService $systemConfig = null,
    ) {
    }

    /**
     * 发送单聊或群聊消息。
     *
     * @param int $senderId 发送用户ID
     * @param array<string,mixed> $input 已验证消息输入
     * @return array<string,mixed>
     */
    public function sendMessage(int $senderId, array $input): array
    {
        $conversationId = (int)$input['conversation_id'];
        $clientMsgId = (string)$input['client_msg_id'];
        /** @var MessageType $messageType */
        $messageType = $input['message_type'];
        $hashPayload = [
            'conversation_id' => $conversationId,
            'message_type' => $messageType->value,
            'body_text' => $input['body_text'],
            'reply_message_id' => $input['reply_message_id'],
            'attachments' => $input['attachments'],
        ];
        $payloadHash = hash('sha256', json_encode(
            $hashPayload,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        ));

        $existing = AppMessageModel::query()
            ->where('sender_id', $senderId)
            ->where('client_msg_id', $clientMsgId)
            ->first();

        if ($existing instanceof AppMessageModel) {
            $this->assertIdempotentPayload($existing, $payloadHash);
            return $this->messageResponse($existing, true);
        }

        try {
            /** @var AppMessageModel $message */
            $message = $this->transactionManager->run(function () use ($senderId, $conversationId, $clientMsgId, $messageType, $input, $payloadHash): AppMessageModel {
                [$conversation, $memberUserIds] = $this->lockSendableConversation($conversationId, $senderId);
                $seq = ((int)$conversation->last_seq) + 1;
                $now = time();
                $replySnapshot = $this->buildReplySnapshot(
                    (int)$conversation->conversation_id,
                    $senderId,
                    $input['reply_message_id'],
                );
                $attachmentRows = $this->resolveAttachmentRows(
                    $senderId,
                    $messageType,
                    $input['attachments'],
                    $now,
                );
                $senderSnapshot = $this->buildSenderSnapshot($senderId);

                $message = AppMessageModel::query()->create([
                    'conversation_id' => (int)$conversation->conversation_id,
                    'seq' => $seq,
                    'sender_id' => $senderId,
                    'sender_snapshot' => $senderSnapshot,
                    'client_msg_id' => $clientMsgId,
                    'message_type' => $messageType->value,
                    'body_text' => $input['body_text'],
                    'mention_all' => 0,
                    'mention_user_ids' => null,
                    'mention_users' => null,
                    'payload_hash' => $payloadHash,
                    'reply_message_id' => $input['reply_message_id'],
                    'reply_snapshot' => $replySnapshot,
                    'extra' => null,
                    'status' => MessageStatus::Normal->value,
                    'create_time' => $now,
                    'update_time' => $now,
                ]);

                foreach ($attachmentRows as $attachmentRow) {
                    AppMessageAttachmentModel::query()->create([
                        'message_id' => (int)$message->message_id,
                    ] + $attachmentRow);
                }

                $message->load(['attachments.file', 'attachments.thumbnailFile']);

                AppConversationModel::query()
                    ->where('conversation_id', (int)$conversation->conversation_id)
                    ->update([
                        'last_message_id' => (int)$message->message_id,
                        'last_seq' => $seq,
                        'update_time' => $now,
                    ]);

                AppConversationMemberModel::query()
                    ->where('conversation_id', (int)$conversation->conversation_id)
                    ->where('user_id', '<>', $senderId)
                    ->whereIn('user_id', $memberUserIds)
                    ->update([
                        'unread_count' => Manager::raw('unread_count + 1'),
                        'is_hidden' => 0,
                        'update_time' => $now,
                    ]);

                AppConversationMemberModel::query()
                    ->where('conversation_id', (int)$conversation->conversation_id)
                    ->where('user_id', $senderId)
                    ->update([
                        'is_hidden' => 0,
                        'update_time' => $now,
                    ]);

                $memberStates = AppConversationMemberModel::query()
                    ->where('conversation_id', (int)$conversation->conversation_id)
                    ->whereIn('user_id', $memberUserIds)
                    ->get()
                    ->keyBy('user_id');

                $maxEventId = 0;
                foreach ($memberUserIds as $eventUserId) {
                    $member = $memberStates->get($eventUserId);
                    if (!$member instanceof AppConversationMemberModel) {
                        throw new BusinessException('IM_MEMBER_NOT_FOUND', '会话成员状态不存在', 500);
                    }

                    $eventId = $this->createMessageEvent($eventUserId, $message, $member, $now);
                    $maxEventId = max($maxEventId, $eventId);

                    AppConversationMemberModel::query()
                        ->where('conversation_id', (int)$conversation->conversation_id)
                        ->where('user_id', $eventUserId)
                        ->update(['last_event_id' => $eventId]);
                }

                AppConversationModel::query()
                    ->where('conversation_id', (int)$conversation->conversation_id)
                    ->update(['last_event_id' => $maxEventId]);

                return $message;
            });
        } catch (QueryException $exception) {
            $message = $this->resolveDuplicateClientMessage($exception, $senderId, $clientMsgId, $payloadHash);
            if (!$message instanceof AppMessageModel) {
                throw $exception;
            }

            return $this->messageResponse($message, true);
        }

        return $this->messageResponse($message, false);
    }

    /** 解析或创建当前用户与目标用户的单聊会话。 */
    public function resolveSingleConversation(int $userId, int $targetUserId): array
    {
        if ($userId === $targetUserId) {
            throw new BusinessException('IM_SELF_CHAT_NOT_ALLOWED', '不能与自己创建单聊会话', 422);
        }
        $this->assertRecipientAvailable($targetUserId);
        $this->assertSenderNotBlocked($userId, $targetUserId);
        $this->assertPrivateChatAllowed($userId, $targetUserId);

        $chatKey = 'single:' . min($userId, $targetUserId) . ':' . max($userId, $targetUserId);
        $created = !AppConversationModel::query()->where('chat_key', $chatKey)->exists();
        $conversation = $this->transactionManager->run(
            fn (): AppConversationModel => $this->createOrGetSingleConversation($userId, $targetUserId),
        );

        $row = $this->conversationProjectionQuery($userId)
            ->where('c.conversation_id', (int)$conversation->conversation_id)
            ->first($this->conversationProjectionColumns());
        if (!is_object($row)) {
            throw new BusinessException('IM_CONVERSATION_NOT_FOUND', '会话不存在或不可用', 404);
        }

        return $this->resolvedSingleConversationRow(
            $this->queryRowAttributes($row),
            $created,
        );
    }

    /** 获取当前用户的单聊会话列表。 */
    public function listConversations(int $userId, int $limit, ?int $beforeUpdateTime, ?int $beforeConversationId): array
    {
        $query = $this->conversationProjectionQuery($userId)
            ->where('cm.is_hidden', 0)
            ->orderByDesc('c.update_time')
            ->orderByDesc('c.conversation_id')
            ->limit($limit);

        if ($beforeUpdateTime !== null && $beforeConversationId !== null) {
            $query->where(static function ($cursorQuery) use ($beforeUpdateTime, $beforeConversationId): void {
                $cursorQuery
                    ->where('c.update_time', '<', $beforeUpdateTime)
                    ->orWhere(static function ($sameTimeQuery) use ($beforeUpdateTime, $beforeConversationId): void {
                        $sameTimeQuery
                            ->where('c.update_time', $beforeUpdateTime)
                            ->where('c.conversation_id', '<', $beforeConversationId);
                    });
            });
        } elseif ($beforeUpdateTime !== null) {
            $query->where('c.update_time', '<', $beforeUpdateTime);
        }

        $rows = $query->get($this->conversationProjectionColumns());

        return [
            'items' => $rows->map(fn (object $row): array => $this->conversationRow($this->queryRowAttributes($row)))->all(),
            'next_before_update_time' => $rows->isEmpty() ? null : (int)$rows->last()->conversation_update_time,
            'next_before_conversation_id' => $rows->isEmpty() ? null : (int)$rows->last()->conversation_id,
        ];
    }

    /**
     * 创建会话列表与单会话接口共用的投影查询。
     *
     * 隐藏状态属于列表筛选条件，不属于投影字段，因此由列表调用方单独过滤；
     * `/conversations/single` 即使命中已隐藏会话，也仍可返回该会话的完整当前视图。
     *
     * @return Builder<AppConversationMemberModel>
     */
    private function conversationProjectionQuery(int $userId): Builder
    {
        return AppConversationMemberModel::query()
            ->from('app_conversation_member as cm')
            ->join('app_conversation as c', 'c.conversation_id', '=', 'cm.conversation_id')
            ->leftJoin('app_conversation_member as peer_cm', static function (JoinClause $join) use ($userId): void {
                $join
                    ->on('peer_cm.conversation_id', '=', 'c.conversation_id')
                    ->where('peer_cm.user_id', '<>', $userId)
                    ->where('c.conversation_type', '=', ConversationType::Single->value);
            })
            ->leftJoin('app_user as peer_user', 'peer_user.user_id', '=', 'peer_cm.user_id')
            ->leftJoin('app_friend as friend', static function (JoinClause $join) use ($userId): void {
                $join
                    ->on('friend.friend_user_id', '=', 'peer_user.user_id')
                    ->where('friend.create_user', '=', $userId)
                    ->where('friend.status', '=', FriendStatus::Friend->value)
                    ->whereNull('friend.delete_time');
            })
            ->leftJoin('app_file as peer_avatar', 'peer_avatar.resource_id', '=', 'peer_user.avatar_resource')
            ->leftJoin('app_message as m', 'm.message_id', '=', 'c.last_message_id')
            ->leftJoin('app_user as last_sender', 'last_sender.user_id', '=', 'm.sender_id')
            ->leftJoin('app_file as last_sender_avatar', static function (JoinClause $join): void {
                $join
                    ->on('last_sender_avatar.resource_id', '=', 'last_sender.avatar_resource')
                    ->where('last_sender_avatar.status', '=', 20);
            })
            ->leftJoin('app_message_user_state as mus', static function (JoinClause $join) use ($userId): void {
                $join
                    ->on('mus.message_id', '=', 'm.message_id')
                    ->where('mus.user_id', '=', $userId);
            })
            ->where('cm.user_id', $userId)
            ->where('c.conversation_type', ConversationType::Single->value)
            ->where('c.status', 10);
    }

    /**
     * 返回完整会话投影所需的数据库字段。
     *
     * @return list<string>
     */
    private function conversationProjectionColumns(): array
    {
        return [
            'c.conversation_id',
            'c.conversation_type',
            'cm.user_id as self_user_id',
            'peer_user.user_id as single_target_id',
            'peer_user.name as single_title',
            'friend.nickname as single_remark',
            'peer_avatar.src as single_avatar_url',
            'c.last_message_id',
            'c.last_seq',
            'c.update_time as conversation_update_time',
            'cm.last_read_seq',
            'cm.last_mention_seq',
            'peer_cm.last_read_seq as peer_last_read_seq',
            'cm.cleared_before_seq',
            'cm.join_seq',
            'cm.history_end_seq',
            'cm.unread_count',
            'cm.is_pinned',
            'cm.is_muted',
            'm.sender_id as last_sender_id',
            'm.sender_snapshot as last_sender_snapshot',
            'last_sender.name as last_sender_name',
            'last_sender.status as last_sender_status',
            'last_sender.avatar_resource as last_sender_avatar_resource',
            'last_sender_avatar.src as last_sender_avatar_url',
            'm.message_type as last_message_type',
            'm.body_text as last_body_text',
            'm.mention_all as last_mention_all',
            'm.mention_user_ids as last_mention_user_ids',
            'm.mention_users as last_mention_users',
            'm.reply_message_id as last_reply_message_id',
            'm.reply_snapshot as last_reply_snapshot',
            'm.status as last_message_status',
            'm.create_time as last_message_time',
            'mus.is_deleted as last_message_deleted',
        ];
    }

    /**
     * 获取会话消息历史。
     *
     * @param int $userId 当前用户ID
     * @param int $conversationId 会话ID
     * @param int $limit 分页条数
     * @param int|null $beforeSeq 分页消息序号
     * @return array<string,mixed>
     */
    public function listMessages(int $userId, int $conversationId, int $limit, ?int $beforeSeq): array
    {
        $member = AppConversationMemberModel::query()
            ->where('conversation_id', $conversationId)
            ->where('user_id', $userId)
            ->first();

        if (!$member instanceof AppConversationMemberModel) {
            throw new BusinessException('IM_CONVERSATION_FORBIDDEN', '无权访问该会话', 403);
        }

        $conversation = AppConversationModel::query()
            ->whereKey($conversationId)
            ->where('status', 10)
            ->first();
        if (!$conversation instanceof AppConversationModel || $conversation->conversation_type !== ConversationType::Single) {
            throw new BusinessException('IM_CONVERSATION_NOT_FOUND', '会话不存在或不可用', 404);
        }

        $query = AppMessageModel::query()
            ->with([
                'attachments.file',
                'attachments.thumbnailFile',
                'sender.avatarFile',
                'replyTarget.attachments.file',
                'replyTarget.attachments.thumbnailFile',
            ])
            ->where('conversation_id', $conversationId)
            ->tap(static fn ($query) => ConversationHistoryAccess::constrain($query, $member))
            ->whereIn('status', [MessageStatus::Normal->value, MessageStatus::Recalled->value])
            ->whereNotExists(static function ($stateQuery) use ($userId): void {
                $stateQuery
                    ->selectRaw('1')
                    ->from('app_message_user_state as mus')
                    ->whereColumn('mus.message_id', 'app_message.message_id')
                    ->where('mus.user_id', $userId)
                    ->where('mus.is_deleted', 1);
            })
            ->orderByDesc('seq')
            ->limit($limit);

        if ($beforeSeq !== null) {
            $query->where('seq', '<', $beforeSeq);
        }

        $messages = $query->get();
        return [
            'items' => $messages->sortBy('seq')->values()->map(
                fn (AppMessageModel $message): array => $this->messageHistoryRow(
                    $message,
                    $userId,
                ),
            )->all(),
            'read_state' => $this->historyReadState($conversation, $member),
            'next_before_seq' => $messages->isEmpty() ? null : (int)$messages->last()->seq,
        ];
    }

    /** 锁定单聊会话并确认双方仍可通信。 */
    private function lockSendableConversation(int $conversationId, int $senderId): array
    {
        $conversation = AppConversationModel::query()
            ->where('conversation_id', $conversationId)
            ->lockForUpdate()
            ->first();
        if (!$conversation instanceof AppConversationModel) {
            throw new BusinessException('IM_CONVERSATION_NOT_FOUND', '会话不存在', 404);
        }
        if ((int)$conversation->status !== 10 || $conversation->conversation_type !== ConversationType::Single) {
            throw new BusinessException('IM_CONVERSATION_UNAVAILABLE', '社区版仅支持单聊', 422);
        }
        $participantIds = $this->singleParticipantUserIds((string)$conversation->chat_key);
        if (count($participantIds) !== 2 || !in_array($senderId, $participantIds, true)) {
            throw new BusinessException('IM_MEMBER_NOT_FOUND', '当前用户不是单聊参与者', 403);
        }
        $recipientId = $participantIds[0] === $senderId ? $participantIds[1] : $participantIds[0];
        $this->assertRecipientAvailable($recipientId);
        $this->assertSenderNotBlocked($senderId, $recipientId);
        $this->assertPrivateChatAllowed($senderId, $recipientId);
        $this->restoreMissingConversationMembers($conversation, array_fill_keys($participantIds, 10), time());

        return [$conversation, $participantIds];
    }

    /** 恢复单聊参与者删除的会话记录，隔离删除前的历史。 */
    private function restoreMissingConversationMembers(
        AppConversationModel $conversation,
        array $memberRoles,
        int $now,
        array $memberSettings = [],
    ): void
    {
        if ($memberRoles === []) {
            return;
        }

        $conversationId = (int)$conversation->conversation_id;
        $existingUserIds = AppConversationMemberModel::query()
            ->where('conversation_id', $conversationId)
            ->whereIn('user_id', array_keys($memberRoles))
            ->pluck('user_id')
            ->map(static fn (mixed $userId): int => (int)$userId)
            ->all();
        $missingUserIds = array_values(array_diff(array_keys($memberRoles), $existingUserIds));
        if ($missingUserIds === []) {
            return;
        }

        $baselineSeq = (int)$conversation->last_seq;
        $rows = $this->buildRestoredConversationMemberRows(
            $conversationId,
            $baselineSeq,
            $memberRoles,
            $missingUserIds,
            $now,
            $memberSettings,
        );
        Manager::table('app_conversation_member')->insertOrIgnore($rows);
    }

    /**
     * 构造恢复用户会话记录的数据库行。
     *
     * @param array<int,int> $memberRoles 用户ID到会话角色的映射
     * @param list<int> $missingUserIds 缺失会话记录的用户ID
     * @param array<int,array{is_pinned:int,is_muted:int}> $memberSettings 缺失成员需要继承的群个人设置
     * @return list<array<string,int>>
     */
    private function buildRestoredConversationMemberRows(
        int $conversationId,
        int $baselineSeq,
        array $memberRoles,
        array $missingUserIds,
        int $now,
        array $memberSettings = [],
    ): array {
        $rows = [];
        foreach ($missingUserIds as $missingUserId) {
            $rows[] = [
                'conversation_id' => $conversationId,
                'user_id' => $missingUserId,
                'member_role' => $memberRoles[$missingUserId],
                'join_seq' => $baselineSeq,
                'last_read_seq' => $baselineSeq,
                'cleared_before_seq' => $baselineSeq,
                'unread_count' => 0,
                'is_pinned' => $memberSettings[$missingUserId]['is_pinned'] ?? 0,
                'is_muted' => $memberSettings[$missingUserId]['is_muted'] ?? 0,
                'is_hidden' => 0,
                'last_event_id' => 0,
                'create_time' => $now,
                'update_time' => $now,
            ];
        }

        return $rows;
    }

    /**
     * 从单聊共享线程业务键解析双方用户ID。
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
     * 确认接收用户可用。
     *
     * @param int $recipientUserId 接收用户ID
     * @return void
     */
    private function assertRecipientAvailable(int $recipientUserId): void
    {
        $recipient = AppUserModel::query()
            ->where('user_id', $recipientUserId)
            ->where('status', UserStatus::Active->value)
            ->first();

        if (!$recipient instanceof AppUserModel) {
            throw new BusinessException('IM_RECIPIENT_UNAVAILABLE', '接收用户不存在或不可用', 422);
        }
    }

    /**
     * 确认接收方未拉黑发送方。
     *
     * 旧好友表仍是当前拉黑事实来源；非好友本身不阻止私聊。
     *
     * @param int $senderId 发送用户ID
     * @param int $recipientUserId 接收用户ID
     * @return void
     */
    private function assertSenderNotBlocked(int $senderId, int $recipientUserId): void
    {
        $blocked = Manager::table('app_friend')
            ->where('create_user', $recipientUserId)
            ->where('friend_user_id', $senderId)
            ->where('status', -2)
            ->whereNull('delete_time')
            ->exists();

        if ($blocked) {
            throw new BusinessException('IM_SENDER_BLOCKED', '对方当前不接收你的消息', 403);
        }
    }

    /**
     * 确认幂等消息载荷未发生变化。
     *
     * @param AppMessageModel $message 已存在消息
     * @param string $payloadHash 当前请求载荷摘要
     * @return void
     */
    private function assertIdempotentPayload(AppMessageModel $message, string $payloadHash): void
    {
        if ((string)$message->payload_hash !== $payloadHash) {
            throw new BusinessException('IM_MESSAGE_IDEMPOTENCY_CONFLICT', '客户端消息ID已用于不同消息内容', 409);
        }
    }

    /**
     * 解析并发下的客户端消息ID重复写入。
     *
     * @param QueryException $exception 数据库异常
     * @param int $senderId 发送用户ID
     * @param string $clientMsgId 客户端消息ID
     * @param string $payloadHash 当前请求载荷摘要
     * @return AppMessageModel|null
     */
    private function resolveDuplicateClientMessage(QueryException $exception, int $senderId, string $clientMsgId, string $payloadHash): ?AppMessageModel
    {
        if ((string)$exception->getCode() !== '23000') {
            return null;
        }

        $message = AppMessageModel::query()
            ->where('sender_id', $senderId)
            ->where('client_msg_id', $clientMsgId)
            ->first();

        if (!$message instanceof AppMessageModel) {
            return null;
        }

        $this->assertIdempotentPayload($message, $payloadHash);

        return $message;
    }

    /**
     * 创建或获取单聊会话。
     *
     * @param int $senderId 发送用户ID
     * @param int $recipientUserId 接收用户ID
     * @return AppConversationModel
     */
    private function createOrGetSingleConversation(int $senderId, int $recipientUserId): AppConversationModel
    {
        $minUserId = min($senderId, $recipientUserId);
        $maxUserId = max($senderId, $recipientUserId);
        $chatKey = 'single:' . $minUserId . ':' . $maxUserId;
        $now = time();

        Manager::table('app_conversation')->insertOrIgnore([
            'conversation_type' => ConversationType::Single->value,
            'target_id' => 0,
            'chat_key' => $chatKey,
            'last_seq' => 0,
            'status' => 10,
            'create_time' => $now,
            'update_time' => $now,
        ]);

        $conversation = AppConversationModel::query()
            ->where('chat_key', $chatKey)
            ->lockForUpdate()
            ->first();

        if (!$conversation instanceof AppConversationModel) {
            throw new BusinessException('IM_CONVERSATION_CREATE_FAILED', '创建会话失败', 500);
        }

        if ((int)$conversation->status !== 10) {
            throw new BusinessException('IM_CONVERSATION_UNAVAILABLE', '会话不可用', 422);
        }

        $this->restoreMissingConversationMembers($conversation, [
            $senderId => 10,
            $recipientUserId => 10,
        ], $now);

        return $conversation;
    }

    /** 关闭陌生人聊天后，创建会话和发送消息均要求发送方仍持有有效好友关系。 */
    private function assertPrivateChatAllowed(int $senderId, int $recipientUserId): void
    {
        if ($this->systemConfig === null || $this->systemConfig->strangerPrivateChatEnabled()) return;
        $isFriend = AppFriendModel::query()->where('create_user', $senderId)
            ->where('friend_user_id', $recipientUserId)->where('status', FriendStatus::Friend->value)
            ->whereNull('delete_time')->exists();
        if (!$isFriend) throw new BusinessException('IM_PRIVATE_CHAT_DISABLED', '当前仅允许好友之间私聊', 403);
    }

    /**
     * 构造同会话引用消息快照。
     *
     * @return array<string,mixed>|null
     */
    private function buildReplySnapshot(int $conversationId, int $userId, ?int $replyMessageId): ?array
    {
        if ($replyMessageId === null) {
            return null;
        }

        $member = AppConversationMemberModel::query()
            ->where('conversation_id', $conversationId)
            ->where('user_id', $userId)
            ->first();
        if (!$member instanceof AppConversationMemberModel) {
            throw new BusinessException('IM_MEMBER_NOT_FOUND', '当前用户不是会话成员', 403);
        }

        $reply = AppMessageModel::query()
            ->with(['attachments.file', 'attachments.thumbnailFile'])
            ->whereKey($replyMessageId)
            ->where('conversation_id', $conversationId)
            ->where('status', MessageStatus::Normal->value)
            ->tap(static fn ($query) => ConversationHistoryAccess::constrain($query, $member))
            ->whereNotExists(static function ($stateQuery) use ($userId): void {
                $stateQuery
                    ->selectRaw('1')
                    ->from('app_message_user_state as mus')
                    ->whereColumn('mus.message_id', 'app_message.message_id')
                    ->where('mus.user_id', $userId)
                    ->where('mus.is_deleted', 1);
            })
            ->first();
        if (!$reply instanceof AppMessageModel) {
            throw new BusinessException('IM_REPLY_MESSAGE_INVALID', '引用消息不存在或当前不可引用', 422);
        }

        $sender = AppUserModel::query()->whereKey((int)$reply->sender_id)->first();
        $messageType = $reply->message_type instanceof MessageType
            ? $reply->message_type
            : MessageType::from((string)$reply->message_type);

        return [
            'snapshot_version' => 1,
            'message_id' => (string)$reply->message_id,
            'seq' => (string)$reply->seq,
            'sender_id' => (string)$reply->sender_id,
            'sender_name' => $sender instanceof AppUserModel ? $this->userDisplayName($sender) : '',
            'message_type' => $messageType->value,
            'is_available' => true,
            'unavailable_reason' => null,
            'summary' => $this->replySummary($reply, $messageType),
            'preview' => $this->replyPreview($reply, $messageType),
            'attachment_count' => $reply->attachments->count(),
        ];
    }

    /**
     * 生成引用卡片的稳定摘要。
     */
    /** 生成文本、图片或文件引用卡片的摘要。 */
    private function replySummary(AppMessageModel $message, MessageType $messageType): string
    {
        $firstAttachment = $message->attachments->first();
        return match ($messageType) {
            MessageType::Text => mb_substr((string)$message->body_text, 0, 200, 'UTF-8'),
            MessageType::Image => '[图片]',
            MessageType::File => trim((string)($firstAttachment?->file_name ?? '')) ?: '[文件]',
        };
    }

    /** 构造基础消息的紧凑引用预览。 */
    private function replyPreview(AppMessageModel $message, MessageType $messageType): ?array
    {
        $attachment = $message->attachments->first();
        if ($messageType === MessageType::Image) {
            if (!$attachment instanceof AppMessageAttachmentModel) return null;
            return [
                'kind' => 'image',
                'resource_id' => $attachment->file instanceof AppFileModel ? (string)$attachment->file->resource_id : null,
                'thumbnail_resource_id' => $attachment->thumbnailFile instanceof AppFileModel ? (string)$attachment->thumbnailFile->resource_id : null,
                'preview_url' => $attachment->thumbnail_url ?: $attachment->resource_url,
                'width' => $attachment->width,
                'height' => $attachment->height,
                'duration_ms' => null,
            ];
        }
        if ($messageType === MessageType::File && $attachment instanceof AppMessageAttachmentModel) {
            return [
                'kind' => 'file',
                'file_name' => $attachment->file_name,
                'file_size' => (int)$attachment->file_size,
                'mime_type' => (string)$attachment->mime_type,
            ];
        }
        return null;
    }

    private function normalizeReplySnapshot(?array $snapshot, bool $forceUnavailable = false): ?array
    {
        if ($snapshot === null) {
            return null;
        }

        $messageType = MessageType::tryFrom((string)($snapshot['message_type'] ?? ''));
        $isAvailable = !$forceUnavailable && (bool)($snapshot['is_available'] ?? true);
        $summary = isset($snapshot['summary']) && trim((string)$snapshot['summary']) !== ''
            ? (string)$snapshot['summary']
            : match ($messageType) {
                MessageType::Image => '[图片]',
                MessageType::File => '[文件]',
                default => '[消息]',
            };

        if (!$isAvailable) {
            $summary = '原消息已撤回';
        }

        $normalized = [
            'snapshot_version' => (int)($snapshot['snapshot_version'] ?? 1),
            'message_id' => isset($snapshot['message_id']) ? (string)$snapshot['message_id'] : null,
            'seq' => isset($snapshot['seq']) ? (string)$snapshot['seq'] : null,
            'sender_id' => isset($snapshot['sender_id']) ? (string)$snapshot['sender_id'] : null,
            'sender_name' => (string)($snapshot['sender_name'] ?? ''),
            'message_type' => $messageType?->value,
            'is_available' => $isAvailable,
            'unavailable_reason' => $isAvailable ? null : (string)($snapshot['unavailable_reason'] ?? 'recalled'),
            'summary' => $summary,
            'preview' => $isAvailable && isset($snapshot['preview']) && is_array($snapshot['preview'])
                ? $snapshot['preview']
                : null,
            'attachment_count' => (int)($snapshot['attachment_count'] ?? 0),
        ];

        return $normalized;
    }

    /**
     * 使用仍可用的原消息补全存量引用快照。
     *
     * @param array<string,mixed>|null $snapshot 数据库存量快照
     * @return array<string,mixed>|null
     */
    private function completeReplySnapshot(?array $snapshot, ?AppMessageModel $replyTarget): ?array
    {
        if ($snapshot === null || !$replyTarget instanceof AppMessageModel) {
            return $this->normalizeReplySnapshot($snapshot);
        }

        $status = $replyTarget->status instanceof MessageStatus
            ? $replyTarget->status
            : MessageStatus::from((int)$replyTarget->status);
        if ($status === MessageStatus::Recalled) {
            return $this->normalizeReplySnapshot($snapshot, true);
        }
        if ($status !== MessageStatus::Normal) {
            return $this->normalizeReplySnapshot($snapshot);
        }

        $messageType = $replyTarget->message_type instanceof MessageType
            ? $replyTarget->message_type
            : MessageType::from((string)$replyTarget->message_type);
        $snapshot['snapshot_version'] = 1;
        $snapshot['message_id'] = (string)$replyTarget->message_id;
        $snapshot['seq'] = (string)$replyTarget->seq;
        $snapshot['sender_id'] = (string)$replyTarget->sender_id;
        $snapshot['message_type'] = $messageType->value;
        $snapshot['summary'] = $this->replySummary($replyTarget, $messageType);
        $snapshot['preview'] = $this->replyPreview($replyTarget, $messageType);
        $snapshot['attachment_count'] = $replyTarget->attachments->count();

        return $this->normalizeReplySnapshot($snapshot);
    }

    /**
     * 核验当前用户已完成的文件资源并生成附件快照。
     *
     * @param list<array<string,mixed>> $attachments 已验证附件输入
     * @return list<array<string,mixed>>
     */
    private function resolveAttachmentRows(
        int $senderId,
        MessageType $messageType,
        array $attachments,
        int $now,
    ): array {
        if ($attachments === []) {
            return [];
        }

        $resourceIds = [];
        foreach ($attachments as $attachment) {
            $resourceIds[] = $attachment['resource_id'];
            if ($attachment['thumbnail_resource_id'] !== null) {
                $resourceIds[] = $attachment['thumbnail_resource_id'];
            }
        }

        $resources = AppFileModel::query()
            ->where('user_id', $senderId)
            ->where('purpose', 'message')
            ->where('status', 20)
            ->whereIn('resource_id', array_values(array_unique($resourceIds)))
            ->get()
            ->keyBy('resource_id');

        $rows = [];
        foreach ($attachments as $attachment) {
            $resource = $resources->get($attachment['resource_id']);
            if (!$resource instanceof AppFileModel || $resource->src === null) {
                throw new BusinessException('IM_ATTACHMENT_RESOURCE_INVALID', '附件资源不存在、未完成或不属于当前用户', 422);
            }
            $this->assertAttachmentMimeType($messageType, (string)$resource->mime_type);

            $thumbnail = null;
            if ($attachment['thumbnail_resource_id'] !== null) {
                $thumbnail = $resources->get($attachment['thumbnail_resource_id']);
                if (
                    !$thumbnail instanceof AppFileModel
                    || $thumbnail->src === null
                    || !str_starts_with((string)$thumbnail->mime_type, 'image/')
                ) {
                    throw new BusinessException('IM_ATTACHMENT_THUMBNAIL_INVALID', '缩略图资源无效', 422);
                }
            }

            $rows[] = [
                'file_id' => (int)$resource->file_id,
                'attachment_type' => $messageType->value,
                'resource_url' => (string)$resource->src,
                'thumbnail_file_id' => $thumbnail instanceof AppFileModel ? (int)$thumbnail->file_id : null,
                'thumbnail_url' => $thumbnail instanceof AppFileModel ? (string)$thumbnail->src : null,
                'file_name' => $resource->name,
                'mime_type' => (string)$resource->mime_type,
                'file_size' => (int)$resource->size,
                'width' => $attachment['width'],
                'height' => $attachment['height'],
                'duration_ms' => $attachment['duration_ms'],
                'waveform' => $attachment['waveform'],
                'sort_order' => $attachment['sort_order'],
                'create_time' => $now,
            ];
        }

        return $rows;
    }

    /**
     * 校验附件MIME类型与消息类型一致。
     */
    private function assertAttachmentMimeType(MessageType $messageType, string $mimeType): void
    {
        $valid = match ($messageType) {
            MessageType::Image => str_starts_with($mimeType, 'image/'),
            MessageType::File => true,
            default => false,
        };
        if (!$valid) {
            throw new BusinessException('IM_ATTACHMENT_TYPE_MISMATCH', '附件类型与消息类型不一致', 422);
        }
    }

    /**
     * 构造联系人名片的发送时快照。
     *
     * @param array{shared_user_id:int}|null $contactCard 名片输入
     * @return array<string,mixed>|null
     */
    private function buildSenderSnapshot(int $senderId): array
    {
        $sender = AppUserModel::query()->whereKey($senderId)->first();
        if (!$sender instanceof AppUserModel) {
            throw new BusinessException('IM_SENDER_NOT_FOUND', '消息发送者不存在', 422);
        }

        $avatar = $sender->avatar_resource === null
            ? null
            : AppFileModel::query()->where('resource_id', (string)$sender->avatar_resource)->where('status', 20)->first();

        return [
            'snapshot_version' => 1,
            'name' => $this->globalUserName($sender),
            'avatar_resource_id' => $sender->avatar_resource === null ? null : (string)$sender->avatar_resource,
            'avatar_url' => $avatar instanceof AppFileModel ? (string)$avatar->src : null,
        ];
    }

    /**
     * 返回用户全局昵称；异常空值使用不可变公开ID兜底，避免生成不可展示快照。
     */
    private function globalUserName(AppUserModel $user): string
    {
        $name = trim((string)$user->name);

        return $name !== '' ? $name : (string)$user->public_id;
    }

    /** 获取基础单聊消息发送者的头像 URL。 */
    private function userAvatarUrl(AppUserModel $user): ?string
    {
        if ($user->avatar_resource === null) {
            return null;
        }

        $url = AppFileModel::query()
            ->where('resource_id', $user->avatar_resource)
            ->where('status', 20)
            ->value('src');

        return $url === null ? null : (string)$url;
    }

    /**
     * 生成稳定的用户展示名称。
     */
    private function userDisplayName(AppUserModel $user): string
    {
        $name = trim((string)$user->first_name . ' ' . (string)$user->last_name);

        return $name !== '' ? $name : (string)$user->public_id;
    }

    /** 将消息整理为历史列表响应；社区版只支持单聊。 */
    private function messageHistoryRow(
        AppMessageModel $message,
        int $currentUserId,
    ): array {
        return ConversationHistoryAccess::redactReply(
            $this->messageRow($message),
            $currentUserId,
            (int)$message->conversation_id,
        );
    }

    /**
     * 构造历史响应中的当前用户和单聊对端已读快照。
     *
     * @return array<string,mixed>
     */
    private function historyReadState(
        AppConversationModel $conversation,
        AppConversationMemberModel $member,
    ): array {
        $peer = null;
        if ($conversation->conversation_type === ConversationType::Single) {
            $peerMember = AppConversationMemberModel::query()
                ->where('conversation_id', (int)$conversation->conversation_id)
                ->where('user_id', '<>', (int)$member->user_id)
                ->first();
            if ($peerMember instanceof AppConversationMemberModel) {
                $peer = [
                    'user_id' => (string)$peerMember->user_id,
                    'last_read_seq' => (string)$peerMember->last_read_seq,
                ];
            }
        }

        return [
            'self' => [
                'user_id' => (string)$member->user_id,
                'last_read_seq' => (string)$member->last_read_seq,
            ],
            'peer' => $peer,
        ];
    }

    /**
     * 为单个会话成员创建新消息事件和待发布Outbox任务。
     *
     * 事件与消息共用同一数据库事务，保证离线同步和后续实时发布都不会漏消息。
     *
     * @param int $userId 事件接收用户ID
     * @param AppMessageModel $message 新消息
     * @param AppConversationMemberModel $member 接收用户的会话状态
     * @param int $now 当前Unix秒
     * @return int 新事件ID
     */
    private function createMessageEvent(
        int $userId,
        AppMessageModel $message,
        AppConversationMemberModel $member,
        int $now,
    ): int {
        $payload = [
            'message' => $this->eventMessageRow($message),
            'conversation' => $this->eventConversationProjection($userId, $message, $member),
        ];

        return $this->eventWriter->write(
            $userId,
            MessageEventType::MessageCreated,
            (int)$message->conversation_id,
            (int)$message->message_id,
            $payload,
            $now,
        );
    }

    /**
     * 构造实时事件中的完整会话投影，保证客户端可直接创建未知会话。
     *
     * 直播终态会复用此投影，并传入真实最大seq消息；原直播卡片通过事件的message字段独立更新。
     *
     * @return array<string,mixed>
     */
    public function eventConversationProjection(
        int $userId,
        AppMessageModel $message,
        AppConversationMemberModel $member,
        ?int $projectionTime = null,
    ): array {
        $conversation = AppConversationModel::query()->find((int)$message->conversation_id);
        $type = $conversation?->conversation_type instanceof ConversationType
            ? $conversation->conversation_type->value
            : (int)($conversation?->conversation_type ?? 1);
        if ($type !== ConversationType::Single->value) {
            throw new BusinessException('IM_CONVERSATION_UNAVAILABLE', '社区版仅支持单聊', 422);
        }
        $peer = AppConversationMemberModel::query()->where('conversation_id', $message->conversation_id)->where('user_id', '<>', $userId)->first();
        $peerUser = $peer === null ? null : AppUserModel::query()->find((int)$peer->user_id);
        $title = $peerUser instanceof AppUserModel ? $this->globalUserName($peerUser) : '用户';
        $targetId = (int)($peer?->user_id ?? 0);
        return [
            'conversation_id' => (string)$message->conversation_id,
            'conversation_type' => $type,
            'target_id' => (string)$targetId,
            'title' => $title,
            'avatar_url' => $peerUser instanceof AppUserModel ? $this->userAvatarUrl($peerUser) : null,
            'last_message_id' => (string)$message->message_id,
            'last_seq' => (string)$message->seq,
            'unread_count' => (int)$member->unread_count,
            'is_pinned' => (bool)$member->is_pinned,
            'is_muted' => (bool)$member->is_muted,
            'has_unread_mention' => (int)$member->last_mention_seq > (int)$member->last_read_seq,
            'update_time' => $projectionTime ?? (int)$message->create_time,
            'last_message' => $this->eventMessageRow($message),
        ];
    }

    /**
     * 生成消息响应。
     *
     * @param AppMessageModel $message 消息模型
     * @param bool $idempotent 是否命中幂等
     * @return array<string,mixed>
     */
    private function messageResponse(AppMessageModel $message, bool $idempotent): array
    {
        $message->loadMissing([
            'attachments.file',
            'attachments.thumbnailFile',
            'replyTarget.attachments.file',
            'replyTarget.attachments.thumbnailFile',
        ]);

        return [
            'idempotent' => $idempotent,
            'message' => $this->messageRow($message),
        ];
    }

    /**
     * 转换消息行。
     *
     * @param AppMessageModel $message 消息模型
     * @return array<string,mixed>
     */
    private function messageRow(AppMessageModel $message): array
    {
        $messageType = $message->message_type instanceof MessageType ? $message->message_type->value : (string)$message->message_type;
        $status = $message->status instanceof MessageStatus ? $message->status->value : (int)$message->status;
        $replyTarget = $message->relationLoaded('replyTarget')
            ? $message->getRelation('replyTarget')
            : null;

        return [
            'message_id' => (int)$message->message_id,
            'conversation_id' => (int)$message->conversation_id,
            'seq' => (int)$message->seq,
            'sender_id' => (int)$message->sender_id,
            'sender' => $this->messageSenderRow($message),
            'client_msg_id' => (string)$message->client_msg_id,
            'message_type' => $messageType,
            'body_text' => $message->body_text,
            'mention_all' => (bool)$message->mention_all,
            'mention_user_ids' => array_map('strval', is_array($message->mention_user_ids) ? $message->mention_user_ids : []),
            'mention_users' => is_array($message->mention_users) ? $message->mention_users : [],
            'reply_message_id' => $message->reply_message_id === null ? null : (string)$message->reply_message_id,
            'reply' => $this->completeReplySnapshot($message->reply_snapshot, $replyTarget),
            'attachments' => $message->attachments->map(static function (AppMessageAttachmentModel $attachment): array {
                return [
                    'resource_id' => (string)$attachment->file->resource_id,
                    'thumbnail_resource_id' => $attachment->thumbnailFile instanceof AppFileModel
                        ? (string)$attachment->thumbnailFile->resource_id
                        : null,
                    'attachment_type' => $attachment->attachment_type->value,
                    'resource_url' => (string)$attachment->resource_url,
                    'thumbnail_url' => $attachment->thumbnail_url,
                    'file_name' => $attachment->file_name,
                    'mime_type' => (string)$attachment->mime_type,
                    'file_size' => (int)$attachment->file_size,
                    'width' => $attachment->width,
                    'height' => $attachment->height,
                    'duration_ms' => $attachment->duration_ms,
                    'waveform' => $attachment->waveform,
                ];
            })->all(),
            // 基础消息不输出商业类型的扩展载荷。
            'extra' => [],
            'message_status' => $status,
            'recalled_at' => $message->recalled_at === null ? null : (int)$message->recalled_at,
            'recalled_by' => $message->recalled_by === null ? null : (int)$message->recalled_by,
            'recall_reason' => $message->recall_reason,
            'create_time' => (int)$message->create_time,
        ];
    }

    /**
     * 组装可直接渲染的消息发送者资料。
     *
     * 用户退群不会影响app_user查询；只有账号已匿名化、用户缺失或当前头像文件异常时才使用发送时快照。
     *
     * @return array{id:string,name:string,avatar_url:string|null}
     */
    private function messageSenderRow(AppMessageModel $message): array
    {
        $snapshot = is_array($message->sender_snapshot) ? $message->sender_snapshot : [];
        $snapshotName = (string)($snapshot['name'] ?? '');
        $snapshotAvatarUrl = isset($snapshot['avatar_url']) && $snapshot['avatar_url'] !== ''
            ? (string)$snapshot['avatar_url']
            : null;
        $sender = $message->relationLoaded('sender') ? $message->getRelation('sender') : null;

        if (!$sender instanceof AppUserModel || $sender->status === UserStatus::Deleted) {
            return [
                'id' => (string)$message->sender_id,
                'name' => $snapshotName,
                'avatar_url' => $snapshotAvatarUrl,
            ];
        }

        if ($sender->avatar_resource === null) {
            $avatarUrl = null;
        } else {
            $avatar = $sender->relationLoaded('avatarFile') ? $sender->getRelation('avatarFile') : null;
            $avatarUrl = $avatar instanceof AppFileModel ? (string)$avatar->src : $snapshotAvatarUrl;
        }

        return [
            'id' => (string)$message->sender_id,
            'name' => $this->globalUserName($sender),
            'avatar_url' => $avatarUrl,
        ];
    }

    /**
     * 转换用于跨设备同步的消息载荷。
     *
     * bigint 标识转为字符串，避免客户端或中间JSON实现发生整数精度丢失。
     *
     * @param AppMessageModel $message 消息模型
     * @return array<string,mixed>
     */
    public function eventMessageRow(AppMessageModel $message): array
    {
        $message->loadMissing([
            'sender.avatarFile',
            'attachments.file',
            'attachments.thumbnailFile',
            'replyTarget.attachments.file',
            'replyTarget.attachments.thumbnailFile',
        ]);
        $row = $this->messageRow($message);
        $row['message_id'] = (string)$message->message_id;
        $row['conversation_id'] = (string)$message->conversation_id;
        $row['seq'] = (string)$message->seq;
        $row['sender_id'] = (string)$message->sender_id;
        return $row;
    }

    /**
     * 转换会话列表行。
     *
     * @param array<string,mixed> $row 查询行
     * @return array<string,mixed>
     */
    private function conversationRow(array $row): array
    {
        $member = new AppConversationMemberModel([
            'conversation_id' => (int)$row['conversation_id'], 'user_id' => (int)$row['self_user_id'],
            'join_seq' => (int)($row['join_seq'] ?? 0), 'history_end_seq' => $row['history_end_seq'] ?? null,
            'cleared_before_seq' => (int)$row['cleared_before_seq'],
        ]);
        $lastMessageVisible = $row['last_message_id'] !== null
            && ConversationHistoryAccess::contains($member, (int)$row['last_seq'])
            && (int)($row['last_message_deleted'] ?? 0) !== 1
            && (int)$row['last_seq'] > (int)$row['cleared_before_seq'];

        $result = [
            'conversation_id' => (int)$row['conversation_id'],
            'conversation_type' => (int)$row['conversation_type'],
            'target_id' => $this->conversationTargetId($row),
            'title' => $this->conversationTitle($row),
            'avatar_url' => $this->conversationAvatarUrl($row),
            'last_message_id' => !$lastMessageVisible ? null : (int)$row['last_message_id'],
            'last_seq' => (int)$row['last_seq'],
            'last_read_seq' => (int)$row['last_read_seq'],
            'read_state' => [
                'self' => [
                    'user_id' => (string)$row['self_user_id'],
                    'last_read_seq' => (string)$row['last_read_seq'],
                ],
                'peer' => (int)$row['conversation_type'] === ConversationType::Single->value
                    && $row['single_target_id'] !== null
                    ? [
                        'user_id' => (string)$row['single_target_id'],
                        'last_read_seq' => (string)($row['peer_last_read_seq'] ?? 0),
                    ]
                    : null,
            ],
            'cleared_before_seq' => (int)$row['cleared_before_seq'],
            'unread_count' => (int)$row['unread_count'],
            'is_pinned' => (bool)$row['is_pinned'],
            'is_muted' => (bool)$row['is_muted'],
            'has_unread_mention' => (int)$row['last_mention_seq'] > (int)$row['last_read_seq'],
            'update_time' => (int)$row['conversation_update_time'],
            'last_message' => !$lastMessageVisible ? null : [
                'message_id' => (int)$row['last_message_id'],
                'sender_id' => (int)$row['last_sender_id'],
                'sender' => $this->conversationLastSenderRow($row),
                'message_type' => (string)$row['last_message_type'],
                'body_text' => $row['last_body_text'],
                'mention_all' => (bool)($row['last_mention_all'] ?? false),
                'mention_user_ids' => array_map('strval', $this->decodeJsonObject($row['last_mention_user_ids'] ?? null) ?? []),
                'mention_users' => $this->decodeJsonObject($row['last_mention_users'] ?? null) ?? [],
                'reply_message_id' => $row['last_reply_message_id'] === null
                    ? null
                    : (string)$row['last_reply_message_id'],
                'reply' => $this->normalizeReplySnapshot(
                    $this->decodeReplySnapshot($row['last_reply_snapshot'] ?? null),
                ),
                'message_status' => (int)$row['last_message_status'],
                'create_time' => (int)$row['last_message_time'],
            ],
        ];
        if (is_array($result['last_message'])) {
            $result['last_message'] = ConversationHistoryAccess::redactReply($result['last_message'], (int)$row['self_user_id'], (int)$row['conversation_id']);
        }
        return $result;
    }

    /**
     * 转换获取或创建单聊会话的响应。
     *
     * 保留原接口的创建结果标记，其余字段严格复用会话列表项投影。
     *
     * @param array<string,mixed> $row 会话联表查询结果
     * @return array<string,mixed>
     */
    private function resolvedSingleConversationRow(array $row, bool $created): array
    {
        $projection = $this->conversationRow($row);
        $projection['created'] = $created;

        return $projection;
    }

    /**
     * 组装会话最后消息的发送者资料。
     *
     * 会话列表使用一次联表查询取得当前用户和头像，避免对每条会话预览重复查询数据库。
     *
     * @param array<string,mixed> $row 会话联表查询结果
     * @return array{id:string,name:string,avatar_url:string|null}
     */
    private function conversationLastSenderRow(array $row): array
    {
        $snapshot = $this->decodeJsonObject($row['last_sender_snapshot'] ?? null) ?? [];
        $snapshotName = (string)($snapshot['name'] ?? '');
        $snapshotAvatarUrl = isset($snapshot['avatar_url']) && $snapshot['avatar_url'] !== ''
            ? (string)$snapshot['avatar_url']
            : null;
        $currentName = isset($row['last_sender_name']) ? trim((string)$row['last_sender_name']) : '';
        $currentStatus = isset($row['last_sender_status']) ? (int)$row['last_sender_status'] : null;

        if ($currentName === '' || $currentStatus === UserStatus::Deleted->value) {
            return [
                'id' => (string)$row['last_sender_id'],
                'name' => $snapshotName,
                'avatar_url' => $snapshotAvatarUrl,
            ];
        }

        $avatarResource = $row['last_sender_avatar_resource'] ?? null;
        $avatarUrl = $avatarResource === null || $avatarResource === ''
            ? null
            : (($row['last_sender_avatar_url'] ?? null) ?: $snapshotAvatarUrl);

        return [
            'id' => (string)$row['last_sender_id'],
            'name' => $currentName,
            'avatar_url' => $avatarUrl === null ? null : (string)$avatarUrl,
        ];
    }

    /**
     * 解析联表查询返回的引用快照。
     *
     * 联表别名字段不会经过消息模型的 JSON cast，因此生产查询通常返回 JSON 字符串；
     * 单元测试或不同数据库驱动也可能直接返回数组，两种形式均保持相同协议。
     *
     * @return array<string,mixed>|null
     */
    private function decodeReplySnapshot(mixed $snapshot): ?array
    {
        if (is_array($snapshot)) {
            return $snapshot;
        }
        if (!is_string($snapshot) || trim($snapshot) === '') {
            return null;
        }

        $decoded = json_decode($snapshot, true, 512, JSON_THROW_ON_ERROR);

        return is_array($decoded) ? $decoded : null;
    }

    /**
     * 解析联表查询返回的通用JSON对象。
     *
     * @return array<string,mixed>|null
     */
    private function decodeJsonObject(mixed $value): ?array
    {
        if (is_array($value)) {
            return $value;
        }
        if (!is_string($value) || trim($value) === '') {
            return null;
        }

        try {
            $decoded = json_decode($value, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return null;
        }

        return is_array($decoded) ? $decoded : null;
    }

    /**
     * 提取查询行字段。
     *
     * Eloquent 查询即使使用 from/join/select，返回值仍是 Model，不能直接 `(array)$row`。
     *
     * @return array<string,mixed>
     */
    private function queryRowAttributes(object $row): array
    {
        return $row instanceof Model ? $row->getAttributes() : (array)$row;
    }

    /**
     * 返回前端可直接跳转的会话目标ID。
     *
     * 单聊全局会话的 target_id 不是对方用户ID，列表响应必须按当前用户视角转换。
     *
     * @param array<string,mixed> $row 查询行
     */
    private function conversationTargetId(array $row): int
    {
        return (int)($row['single_target_id'] ?? 0);
    }

    /**
     * 返回会话列表标题。
     *
     * @param array<string,mixed> $row 查询行
     */
    private function conversationTitle(array $row): string
    {
        $remark = trim((string)($row['single_remark'] ?? ''));
        if ($remark !== '') {
            return $remark;
        }
        return (string)($row['single_title'] ?? '');
    }

    /**
     * 返回会话列表头像URL。
     *
     * @param array<string,mixed> $row 查询行
     */
    private function conversationAvatarUrl(array $row): ?string
    {
        return $row['single_avatar_url'] === null ? null : (string)$row['single_avatar_url'];
    }
}

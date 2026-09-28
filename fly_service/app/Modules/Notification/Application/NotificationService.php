<?php

declare(strict_types=1);

namespace app\Modules\Notification\Application;

use app\Modules\Im\Application\ConversationHistoryAccess;

use app\enum\ConversationType;
use app\enum\FriendStatus;
use app\enum\MessageEventType;
use app\enum\NotificationActionStatus;
use app\exception\BusinessException;
use app\model\AppConversationMemberModel;
use app\model\AppConversationModel;
use app\model\AppFriendModel;
use app\model\AppSystemNotificationModel;
use app\model\AppSystemNotificationRecipientModel;
use app\model\AppUserModel;
use app\Modules\Im\Application\ImEventWriter;
use app\Modules\Im\Application\ImDirectoryProjectionBuilder;
use app\Support\Request\RequestContext;
use app\Support\Transaction\TransactionManager;
use app\Support\Link\PublicLinkService;
use Illuminate\Database\Capsule\Manager;

/**
 * 系统通知应用服务。
 */
final class NotificationService
{
    /**
     * @param TransactionManager $transactionManager 事务管理器
     * @param ImEventWriter $eventWriter IM事件与Outbox写入器
     */
    public function __construct(
        private readonly TransactionManager $transactionManager,
        private readonly ImEventWriter $eventWriter,
        private readonly ImDirectoryProjectionBuilder $directoryProjections,
        private readonly PublicLinkService $publicLinks,
    ) {
    }

    /**
     * 获取当前用户通知列表。
     *
     * @return array<string,mixed>
     */
    public function list(int $userId, int $limit, ?int $beforeNotificationId): array
    {
        $query = AppSystemNotificationRecipientModel::query()
            ->with('notification')
            ->where('recipient_user_id', $userId)
            ->where('is_deleted', 0)
            ->orderByDesc('notification_id')
            ->limit($limit);

        if ($beforeNotificationId !== null) {
            $query->where('notification_id', '<', $beforeNotificationId);
        }

        $rows = $query->get();
        $sources = $this->notificationSources($rows->all());

        return [
            'items' => $rows
                ->map(fn (AppSystemNotificationRecipientModel $recipient): array => $this->recipientRow($recipient, $sources))
                ->all(),
            'nextCursor' => $rows->isEmpty() ? null : (string)$rows->last()->notification_id,
        ];
    }

    /**
     * 获取当前用户未读通知数量。
     *
     * @return array<string,mixed>
     */
    public function unreadCount(int $userId): array
    {
        return [
            'unread_count' => AppSystemNotificationRecipientModel::query()
                ->where('recipient_user_id', $userId)
                ->where('is_read', 0)
                ->where('is_deleted', 0)
                ->count(),
        ];
    }

    /**
     * 标记单条通知为已读。
     *
     * @return array<string,mixed>
     */
    public function markRead(int $userId, int $notificationId): array
    {
        return $this->transactionManager->run(function () use ($userId, $notificationId): array {
            $recipient = $this->lockRecipient($userId, $notificationId);
            if ((int)$recipient->is_read === 1) {
                return $this->recipientRow($recipient);
            }

            $now = time();
            AppSystemNotificationRecipientModel::query()
                ->where('notification_id', $notificationId)
                ->where('recipient_user_id', $userId)
                ->update([
                    'is_read' => 1,
                    'read_at' => $now,
                    'update_time' => $now,
                ]);

            return $this->touchRecipientEvent($userId, $notificationId, $now);
        });
    }

    /**
     * 标记当前用户全部通知为已读。
     *
     * @return array<string,mixed>
     */
    public function markAllRead(int $userId): array
    {
        return $this->transactionManager->run(function () use ($userId): array {
            $now = time();
            $recipients = AppSystemNotificationRecipientModel::query()
                ->where('recipient_user_id', $userId)
                ->where('is_read', 0)
                ->where('is_deleted', 0)
                ->lockForUpdate()
                ->get();

            foreach ($recipients as $recipient) {
                AppSystemNotificationRecipientModel::query()
                    ->where('notification_id', (int)$recipient->notification_id)
                    ->where('recipient_user_id', $userId)
                    ->update([
                        'is_read' => 1,
                        'read_at' => $now,
                        'update_time' => $now,
                    ]);
                $this->touchRecipientEvent($userId, (int)$recipient->notification_id, $now);
            }

            return ['updated_count' => $recipients->count()];
        });
    }

    /**
     * 处理当前用户可操作通知。
     *
     * 处理动作通知，并在同一事务中写入好友或群成员最终业务事实。
     *
     * @return array<string,mixed>
     */
    public function handle(int $userId, int $notificationId, string $action, ?string $reason = null): array
    {
        return $this->transactionManager->run(function () use ($userId, $notificationId, $action, $reason): array {
            $recipient = $this->lockRecipient($userId, $notificationId);
            $notification = $recipient->notification;
            if (!$notification instanceof AppSystemNotificationModel) {
                throw new BusinessException('NOTIFICATION_NOT_FOUND', '通知不存在或不可见', 404);
            }
            $status = $notification->action_status instanceof NotificationActionStatus
                ? $notification->action_status
                : NotificationActionStatus::from((int)$notification->action_status);
            if ($status !== NotificationActionStatus::Pending) {
                throw new BusinessException('NOTIFICATION_STATE_CONFLICT', '通知当前状态不允许处理', 409);
            }
            if ($notification->expire_at !== null && (int)$notification->expire_at < time()) {
                $this->expireNotification($notification, $userId);
                throw new BusinessException('NOTIFICATION_STATE_CONFLICT', '通知已过期', 409);
            }

            $now = time();
            $nextStatus = $action === 'accept'
                ? NotificationActionStatus::Accepted
                : NotificationActionStatus::Rejected;

            $this->applyBusinessAction($notification, $userId, $action, $reason, $now);

            AppSystemNotificationModel::query()
                ->whereKey($notificationId)
                ->update([
                    'action_status' => $nextStatus->value,
                    'active_dedupe_key' => null,
                    'handled_by' => $userId,
                    'handled_at' => $now,
                    'update_time' => $now,
                ]);
            AppSystemNotificationRecipientModel::query()
                ->where('notification_id', $notificationId)
                ->where('recipient_user_id', $userId)
                ->update([
                    'is_read' => 1,
                    'read_at' => $now,
                    'update_time' => $now,
                ]);

            return $this->touchRecipientEvent($userId, $notificationId, $now);
        });
    }

    /**
     * 在通知处理事务中写入最终业务事实。
     */
    private function applyBusinessAction(AppSystemNotificationModel $notification, int $handlerUserId, string $action, ?string $reason, int $now): void
    {
        match ((string)$notification->notification_type) {
            'friend_request' => $this->handleFriendRequest($notification, $handlerUserId, $action, $reason, $now),
            default => throw new BusinessException('NOTIFICATION_ACTION_UNSUPPORTED', '社区版仅支持好友申请处理', 422),
        };
    }

    /**
     * 处理好友申请，接受时写双向好友关系。
     */
    private function handleFriendRequest(AppSystemNotificationModel $notification, int $handlerUserId, string $action, ?string $reason, int $now): void
    {
        $payload = $notification->payload ?? [];
        $fromUserId = (int)($payload['from_user_id'] ?? 0);
        $toUserId = (int)($payload['to_user_id'] ?? 0);
        if ($fromUserId <= 0 || $toUserId !== $handlerUserId) {
            throw new BusinessException('NOTIFICATION_PERMISSION_DENIED', '无权处理该通知', 403);
        }

        if ($action === 'accept') {
            $this->upsertFriend($handlerUserId, $fromUserId, $now);
            $this->upsertFriend($fromUserId, $handlerUserId, $now);
            $this->createNotification(
                'friend_accepted',
                'friend',
                'friend:' . $fromUserId . ':' . $handlerUserId,
                'friend_accepted:' . $fromUserId . ':' . $handlerUserId . ':' . $now,
                $handlerUserId,
                [$fromUserId],
                '好友申请已通过',
                '你的好友申请已通过',
                ['from_user_id' => (string)$fromUserId, 'to_user_id' => (string)$handlerUserId],
                NotificationActionStatus::None,
                $now,
            );
            $this->writeContactConversationEvent($handlerUserId, $fromUserId, 'friend_request_accepted', $now);
            $this->writeContactConversationEvent($fromUserId, $handlerUserId, 'friend_request_accepted', $now);
            return;
        }

        $this->createNotification(
            'friend_rejected',
            'friend',
            'friend:' . $fromUserId . ':' . $handlerUserId,
            'friend_rejected:' . $fromUserId . ':' . $handlerUserId . ':' . $now,
            $handlerUserId,
            [$fromUserId],
            '好友申请已拒绝',
            $this->rejectionContent('你的好友申请已被拒绝', $reason),
            ['from_user_id' => (string)$fromUserId, 'to_user_id' => (string)$handlerUserId, 'reason' => $reason],
            NotificationActionStatus::None,
            $now,
        );
    }

    /**
     * 写好友关系变更事件。
     */
    private function writeContactConversationEvent(int $userId, int $friendUserId, string $reason, int $now): void
    {
        $conversation = $this->singleConversation($userId, $friendUserId);
        $this->eventWriter->writeWithEnvelope(
            $userId,
            MessageEventType::ConversationUpdated,
            $conversation instanceof AppConversationModel ? (int)$conversation->conversation_id : null,
            null,
            [
                'reason' => $reason,
                'contact' => [
                    'user_id' => (string)$friendUserId,
                    'relation_status' => 'friend',
                ],
                'directory_changes' => $this->directoryProjections->contactChanges(
                    $userId,
                    $friendUserId,
                    FriendStatus::Friend,
                ),
            ],
            $now,
        );
    }

    /**
     * 查找双方单聊会话，不主动创建。
     */
    private function singleConversation(int $userId, int $friendUserId): ?AppConversationModel
    {
        $minUserId = min($userId, $friendUserId);
        $maxUserId = max($userId, $friendUserId);
        $conversation = AppConversationModel::query()
            ->where('conversation_type', ConversationType::Single->value)
            ->where('chat_key', 'single:' . $minUserId . ':' . $maxUserId)
            ->first();

        return $conversation instanceof AppConversationModel ? $conversation : null;
    }

    /**
     * 拼接拒绝通知正文。
     */
    private function rejectionContent(string $baseContent, ?string $reason): string
    {
        return $reason === null ? $baseContent : $baseContent . '，原因：' . $reason;
    }

    /**
     * 处理群邀请，接受时写群成员和会话成员。
     */
    private function upsertFriend(int $userId, int $friendUserId, int $now): void
    {
        AppFriendModel::query()->updateOrCreate(
            ['create_user' => $userId, 'friend_user_id' => $friendUserId],
            [
                'status' => FriendStatus::Friend->value,
                'delete_time' => null,
                'update_time' => $now,
                'create_time' => $now,
            ],
        );
    }

    /**
     * 获取正常群。
     */
    private function createNotification(
        string $type,
        string $bizType,
        string $bizId,
        string $dedupeKey,
        ?int $actorUserId,
        array $recipientUserIds,
        string $title,
        ?string $content,
        array $payload,
        NotificationActionStatus $actionStatus,
        int $now,
    ): AppSystemNotificationModel {
        $notification = AppSystemNotificationModel::query()->create([
            'notification_type' => $type,
            'actor_user_id' => $actorUserId,
            'biz_type' => $bizType,
            'biz_id' => $bizId,
            'dedupe_key' => $dedupeKey,
            'active_dedupe_key' => $actionStatus === NotificationActionStatus::Pending ? $dedupeKey : null,
            'title' => $title,
            'content' => $content,
            'payload' => $payload,
            'action_status' => $actionStatus->value,
            'create_time' => $now,
            'update_time' => $now,
        ]);

        foreach (array_values(array_unique($recipientUserIds)) as $recipientUserId) {
            AppSystemNotificationRecipientModel::query()->create([
                'notification_id' => (int)$notification->notification_id,
                'recipient_user_id' => $recipientUserId,
                'is_read' => 0,
                'is_deleted' => 0,
                'last_event_id' => 0,
                'create_time' => $now,
                'update_time' => $now,
            ]);
            $eventId = $this->eventWriter->writeNotification(
                $recipientUserId,
                MessageEventType::NotificationCreated,
                (int)$notification->notification_id,
                $this->notificationRowByNotification($notification),
                $now,
            );
            AppSystemNotificationRecipientModel::query()
                ->where('notification_id', (int)$notification->notification_id)
                ->where('recipient_user_id', $recipientUserId)
                ->update(['last_event_id' => $eventId]);
        }

        return $notification;
    }

    /**
     * 转换通知主记录为同步事件载荷。
     *
     * @return array<string,mixed>
     */
    private function notificationRowByNotification(AppSystemNotificationModel $notification): array
    {
        $status = $notification->action_status instanceof NotificationActionStatus
            ? $notification->action_status
            : NotificationActionStatus::from((int)$notification->action_status);

        return [
            'notification_id' => (string)$notification->notification_id,
            'notification_type' => (string)$notification->notification_type,
            'actor_user_id' => $notification->actor_user_id === null ? null : (string)$notification->actor_user_id,
            'biz_type' => (string)$notification->biz_type,
            'biz_id' => (string)$notification->biz_id,
            'title' => (string)$notification->title,
            'content' => $notification->content,
            'payload' => $notification->payload ?? (object)[],
            'action_status' => $status->apiName(),
            'is_read' => false,
            'read_at' => null,
            'create_time' => (int)$notification->create_time,
            'update_time' => (int)$notification->update_time,
        ];
    }

    /**
     * 仅对当前用户删除通知。
     *
     * @return array<string,mixed>
     */
    public function deleteForMe(int $userId, int $notificationId): array
    {
        return $this->transactionManager->run(function () use ($userId, $notificationId): array {
            $recipient = $this->lockRecipient($userId, $notificationId);
            if ((int)$recipient->is_deleted === 1) {
                return $this->recipientRow($recipient);
            }

            $now = time();
            AppSystemNotificationRecipientModel::query()
                ->where('notification_id', $notificationId)
                ->where('recipient_user_id', $userId)
                ->update([
                    'is_deleted' => 1,
                    'deleted_at' => $now,
                    'update_time' => $now,
                ]);

            return $this->touchRecipientEvent($userId, $notificationId, $now);
        });
    }

    /**
     * 锁定当前用户可见的通知接收人状态。
     */
    private function lockRecipient(int $userId, int $notificationId): AppSystemNotificationRecipientModel
    {
        $recipient = AppSystemNotificationRecipientModel::query()
            ->with('notification')
            ->where('notification_id', $notificationId)
            ->where('recipient_user_id', $userId)
            ->where('is_deleted', 0)
            ->lockForUpdate()
            ->first();

        if (!$recipient instanceof AppSystemNotificationRecipientModel) {
            throw new BusinessException('NOTIFICATION_NOT_FOUND', '通知不存在或不可见', 404);
        }

        return $recipient;
    }

    /**
     * 将通知过期并写状态事件。
     */
    private function expireNotification(AppSystemNotificationModel $notification, int $userId): void
    {
        $now = time();
        AppSystemNotificationModel::query()
            ->whereKey((int)$notification->notification_id)
            ->update([
                'action_status' => NotificationActionStatus::Expired->value,
                'active_dedupe_key' => null,
                'update_time' => $now,
            ]);
        $this->touchRecipientEvent($userId, (int)$notification->notification_id, $now);
    }

    /**
     * 写通知状态变更事件并刷新接收人最近事件ID。
     *
     * @return array<string,mixed>
     */
    private function touchRecipientEvent(int $userId, int $notificationId, int $now): array
    {
        $recipient = AppSystemNotificationRecipientModel::query()
            ->with('notification')
            ->where('notification_id', $notificationId)
            ->where('recipient_user_id', $userId)
            ->first();
        if (!$recipient instanceof AppSystemNotificationRecipientModel) {
            throw new BusinessException('NOTIFICATION_NOT_FOUND', '通知不存在或不可见', 404);
        }

        $payload = $this->recipientRow($recipient);
        $eventId = $this->eventWriter->writeNotification(
            $userId,
            MessageEventType::NotificationUpdated,
            $notificationId,
            $payload,
            $now,
        );
        AppSystemNotificationRecipientModel::query()
            ->where('notification_id', $notificationId)
            ->where('recipient_user_id', $userId)
            ->update(['last_event_id' => $eventId]);

        return $payload + ['event_id' => (string)$eventId];
    }

    /**
     * 转换接收人通知行为API输出。
     *
     * @return array<string,mixed>
     */
    private function recipientRow(AppSystemNotificationRecipientModel $recipient, ?array $sources = null): array
    {
        $notification = $recipient->notification;
        if (!$notification instanceof AppSystemNotificationModel) {
            throw new BusinessException('NOTIFICATION_NOT_FOUND', '通知不存在或不可见', 404);
        }
        $status = $notification->action_status instanceof NotificationActionStatus
            ? $notification->action_status
            : NotificationActionStatus::from((int)$notification->action_status);
        $sources ??= $this->notificationSources([$recipient]);
        $notificationId = (int)$notification->notification_id;

        return [
            'notification_id' => (string)$notification->notification_id,
            'notification_type' => (string)$notification->notification_type,
            'actor_user_id' => $notification->actor_user_id === null ? null : (string)$notification->actor_user_id,
            'actor_user' => $sources['actors'][$notificationId] ?? null,
            'biz_type' => (string)$notification->biz_type,
            'biz_id' => (string)$notification->biz_id,
            'group' => $sources['groups'][$notificationId] ?? null,
            'title' => (string)$notification->title,
            'content' => $notification->content,
            'payload' => $notification->payload ?? (object)[],
            'action_status' => $status->apiName(),
            'is_read' => (int)$recipient->is_read === 1,
            'read_at' => $recipient->read_at === null ? null : (int)$recipient->read_at,
            'create_time' => (int)$notification->create_time,
            'update_time' => (int)$notification->update_time,
        ];
    }

    /**
     * 批量加载通知展示来源，避免通知列表逐条反查头像。
     *
     * @param array<int,AppSystemNotificationRecipientModel> $recipients
     * @return array{actors:array<int,array<string,mixed>|null>,groups:array<int,array<string,mixed>|null>}
     */
    private function notificationSources(array $recipients): array
    {
        $actorUserIds = [];
        $notificationActorMap = [];
        foreach ($recipients as $recipient) {
            $notification = $recipient->notification;
            if (!$notification instanceof AppSystemNotificationModel || $notification->actor_user_id === null) {
                continue;
            }
            $notificationId = (int)$notification->notification_id;
            $actorUserId = (int)$notification->actor_user_id;
            $actorUserIds[] = $actorUserId;
            $notificationActorMap[$notificationId] = $actorUserId;
        }
        $actors = $this->actorRows(array_values(array_unique($actorUserIds)));
        $sourceActors = [];
        foreach ($notificationActorMap as $notificationId => $actorUserId) {
            $sourceActors[$notificationId] = $actors[$actorUserId] ?? null;
        }
        return ['actors' => $sourceActors, 'groups' => []];
    }

    /** 批量构造好友申请触发用户的展示资料。 */
    private function actorRows(array $userIds): array
    {
        if ($userIds === []) {
            return [];
        }

        $rows = AppUserModel::query()
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'app_user.avatar_resource')
            ->whereIn('app_user.user_id', $userIds)
            ->select([
                'app_user.user_id',
                'app_user.public_id',
                'app_user.username',
                'app_user.name',
                'avatar.src as avatar_url',
            ])
            ->get();

        $actors = [];
        foreach ($rows as $row) {
            $username = $row->username === null ? null : (string)$row->username;
            $actors[(int)$row->user_id] = [
                'id' => (string)$row->user_id,
                'public_id' => (string)$row->public_id,
                'username' => $username === null ? null : '@' . $username,
                'profile_path' => $username === null ? null : $this->publicLinks->userPath($username),
                'profile_url' => $username === null ? null : $this->publicLinks->userUrl($username),
                'name' => (string)$row->name,
                'avatar_url' => $row->avatar_url ?? null,
            ];
        }

        return $actors;
    }

    /**
     * 批量构造群聊展示信息。
     *
     * @param array<int> $groupIds
     * @return array<int,array<string,mixed>>
     */
}

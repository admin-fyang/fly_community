<?php

declare(strict_types=1);

namespace app\Modules\Contact\Application;

use app\enum\FriendStatus;
use app\enum\ConversationType;
use app\enum\MessageEventType;
use app\enum\NotificationActionStatus;
use app\enum\UserStatus;
use app\exception\BusinessException;
use app\model\AppConversationMemberModel;
use app\model\AppConversationModel;
use app\model\AppFriendModel;
use app\model\AppSystemNotificationModel;
use app\model\AppSystemNotificationRecipientModel;
use app\model\AppUserModel;
use app\Modules\Im\Application\ImEventWriter;
use app\Modules\Im\Application\ImDirectoryProjectionBuilder;
use app\Modules\System\Application\SystemConfigService;
use app\Modules\User\Domain\Exception\UserPresenceUnavailableException;
use app\Modules\User\Domain\Service\UserPresence;
use app\Support\Transaction\TransactionManager;
use app\Support\Link\PublicLinkService;
use Illuminate\Database\Capsule\Manager;
use Illuminate\Database\QueryException;

/**
 * 联系人和好友申请应用服务。
 */
final class ContactService
{
    /**
     * 注入事务、联系方式工具和同步事件写入器。
     */
    public function __construct(
        private readonly TransactionManager $transactionManager,
        private readonly ImEventWriter $eventWriter,
        private readonly ImDirectoryProjectionBuilder $directoryProjections,
        private readonly PublicLinkService $publicLinks,
        private readonly UserPresence $userPresence,
        private readonly SystemConfigService $systemConfig,
        private readonly \app\Modules\Search\Infrastructure\SocialSearchQuery $search,
    ) {
    }

    /**
     * 注册事务内建立默认双向好友；不走好友申请开关，不主动创建单聊会话。
     * 目标失效或存在拉黑关系时返回false，数据库错误仍由注册事务统一回滚。
     */
    public function initializeRegistrationFriend(int $userId, int $targetUserId, int $now): bool
    {
        if ($userId === $targetUserId) return false;
        $target = AppUserModel::query()->whereKey($targetUserId)->where('status', UserStatus::Active->value)->whereNull('delete_time')->sharedLock()->first();
        if (!$target) return false;
        $relations = AppFriendModel::query()->where(function ($query) use ($userId, $targetUserId): void {
            $query->where(fn($pair) => $pair->where('create_user', $userId)->where('friend_user_id', $targetUserId))
                ->orWhere(fn($pair) => $pair->where('create_user', $targetUserId)->where('friend_user_id', $userId));
        })->orderBy('create_user')->lockForUpdate()->get()->keyBy('create_user');
        foreach ($relations as $relation) {
            if ($relation->status === FriendStatus::Blocked) return false;
        }
        $changed = false;
        $owners = [$userId=>$targetUserId, $targetUserId=>$userId];
        ksort($owners);
        foreach ($owners as $ownerId => $peerId) {
            $relation = $relations->get($ownerId);
            if ($relation && $relation->status === FriendStatus::Friend && $relation->delete_time === null) continue;
            $relation ??= new AppFriendModel(['create_user'=>$ownerId, 'friend_user_id'=>$peerId, 'create_time'=>$now, 'is_top'=>0, 'is_notice'=>1]);
            $relation->fill(['status'=>FriendStatus::Friend->value, 'delete_time'=>null, 'update_time'=>$now])->save();
            $this->writeContactConversationEvent($ownerId, $peerId, 'registration_contact_added', $relation, $now);
            $changed = true;
        }
        if ($changed) $this->createNotification('friend_accepted', 'friend', 'friend:'.$userId.':'.$targetUserId,
            'registration_friend:'.$userId.':'.$targetUserId, null, [$userId], '系统已添加联系人',
            '注册初始化已将 '.$target->name.' 添加为你的好友',
            ['user_id'=>(string)$targetUserId, 'friend_user_id'=>(string)$targetUserId, 'source'=>'registration_initialization'], NotificationActionStatus::None);
        return true;
    }

    /**
     * 获取当前用户联系人列表。
     *
     * @return array<string,mixed>
     */
    public function list(int $userId, int $limit, ?int $cursor): array
    {
        $query = Manager::table('app_friend as f')
            ->join('app_user as u', 'u.user_id', '=', 'f.friend_user_id')
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'u.avatar_resource')
            ->where('f.create_user', $userId)
            ->where('f.status', FriendStatus::Friend->value)
            ->whereNull('f.delete_time')
            ->where('u.status', UserStatus::Active->value)
            ->select([
                'f.friend_id',
                'f.nickname',
                'f.is_top',
                'f.is_notice',
                'f.create_time as relation_create_time',
                'f.update_time as relation_update_time',
                'u.user_id',
                'u.public_id',
                'u.username',
                'u.name',
                'u.motto',
                'u.is_auth',
                'u.profile_version',
                'u.last_active_at',
                'avatar.src as avatar_url',
            ])
            ->orderByDesc('f.is_top')
            ->orderBy('u.name')
            ->orderBy('f.friend_id')
            ->limit($limit);

        if ($cursor !== null) {
            $query->where('f.friend_id', '>', $cursor);
        }

        $rows = $query->get();
        $onlineStates = $this->onlineStates(
            $rows->pluck('user_id')->map(static fn (mixed $userId): int => (int)$userId)->all(),
        );

        return [
            'items' => $rows->map(fn (object $row): array => $this->contactRow(
                $userId,
                $row,
                $onlineStates[(int)$row->user_id] ?? null,
            ))->all(),
            'next_cursor' => $rows->isEmpty() ? null : (string)$rows->last()->friend_id,
        ];
    }

    /**
     * 搜索用户。
     *
     * @return array<string,mixed>
     */
    public function searchUsers(int $viewerId, string $keyword, int $limit, ?string $countryCode): array
    {
        $query = AppUserModel::query()
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'app_user.avatar_resource')
            ->where('app_user.status', UserStatus::Active->value)
            ->where('app_user.user_id', '<>', $viewerId)
            ->select([
                'app_user.*',
                'avatar.src as avatar_url',
            ])
            ->limit($limit);

        $this->search->user($query, $keyword);

        $users = $query->get();
        $onlineStates = $this->onlineStates(
            $users->pluck('user_id')->map(static fn (mixed $userId): int => (int)$userId)->all(),
        );

        return [
            'items' => $users->map(function (AppUserModel $user) use ($viewerId, $onlineStates): array {
                $relationship = $this->relationship($viewerId, (int)$user->user_id);

                return [
                    'user' => $this->userBrief($user, $onlineStates[(int)$user->user_id] ?? null),
                    'relationship' => $relationship,
                    'can_add_friend' => $relationship === 'stranger',
                    'has_pending_friend_request' => $this->hasPendingFriendRequest($viewerId, (int)$user->user_id),
                ];
            })->all(),
        ];
    }

    /**
     * 获取指定用户资料。
     *
     * @return array<string,mixed>
     */
    public function profile(int $viewerId, int $targetUserId): array
    {
        $user = AppUserModel::query()
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'app_user.avatar_resource')
            ->where('app_user.user_id', $targetUserId)
            ->where('app_user.status', UserStatus::Active->value)
            ->select(['app_user.*', 'avatar.src as avatar_url'])
            ->first();
        if (!$user instanceof AppUserModel) {
            throw new BusinessException('USER_NOT_FOUND', '用户不存在或不可用', 404);
        }

        $relationship = $viewerId === $targetUserId ? 'self' : $this->relationship($viewerId, $targetUserId);
        $isFriend = $relationship === 'friend' || $relationship === 'self';

        return [
            'user' => $this->userBrief(
                $user,
                $this->onlineStates([$targetUserId])[$targetUserId] ?? null,
            ),
            'relationship' => $relationship,
            'phone' => $this->visibleContact($targetUserId, 10, (int)$user->phone_visibility, $isFriend),
            'birthday' => $this->visibleBirthday($user, $isFriend),
            'region_code' => $user->region_code,
            'register_time' => (int)$user->create_time,
            'can_add_friend' => $relationship === 'stranger',
            'has_pending_friend_request' => $this->hasPendingFriendRequest($viewerId, $targetUserId),
        ];
    }

    /**
     * 发起好友申请。
     *
     * @return array<string,mixed>
     */
    public function sendFriendRequest(int $userId, int $targetUserId, ?string $remark): array
    {
        // 全局关闭好友申请时，在查询用户关系和开启事务前直接拒绝新申请。
        if (!$this->systemConfig->getSwitch('open_add_friend', true)) {
            throw new BusinessException('FRIEND_REQUEST_DISABLED', '好友申请功能已关闭', 403);
        }

        if ($userId === $targetUserId) {
            throw new BusinessException('VALIDATION_ERROR', '不能添加自己为好友', 422);
        }
        $this->assertUserActive($targetUserId);
        $this->assertCanRequestFriend($userId, $targetUserId);

        return $this->transactionManager->run(function () use ($userId, $targetUserId, $remark): array {
            $dedupeKey = 'friend_request:' . $userId . ':' . $targetUserId;
            $existing = $this->pendingNotification($dedupeKey);
            if ($existing instanceof AppSystemNotificationModel) {
                return ['notification' => $this->notificationRow($existing)];
            }

            $actor = AppUserModel::query()->whereKey($userId)->first();
            if (!$actor instanceof AppUserModel) {
                throw new BusinessException('USER_NOT_FOUND', '用户不存在或不可用', 404);
            }
            $notification = $this->createNotification(
                'friend_request',
                'friend',
                'friend:' . $userId . ':' . $targetUserId,
                $dedupeKey,
                $userId,
                [$targetUserId],
                '好友申请',
                $actor->name . ' 请求添加你为好友',
                [
                    'from_user_id' => (string)$userId,
                    'to_user_id' => (string)$targetUserId,
                    'remark' => $remark,
                    'actor_name' => $actor->name,
                ],
                NotificationActionStatus::Pending,
            );

            return ['notification' => $this->notificationRow($notification)];
        });
    }

    /**
     * 修改好友备注。
     *
     * @return array<string,mixed>
     */
    public function updateRemark(int $userId, int $friendUserId, ?string $remark): array
    {
        return $this->transactionManager->run(function () use ($userId, $friendUserId, $remark): array {
            $friend = $this->friendOrFail($userId, $friendUserId);
            $now = time();
            $friend->nickname = $remark;
            $friend->update_time = $now;
            $friend->save();
            $directory = $this->writeContactConversationEvent($userId, $friendUserId, 'contact_remark_updated', $friend, $now);

            return ['user_id' => (string)$friendUserId, 'remark' => $remark, 'update_time' => $now] + $directory;
        });
    }

    /**
     * 修改联系人设置。
     *
     * @return array<string,mixed>
     */
    public function updateSettings(int $userId, int $friendUserId, ?bool $isPinned, ?bool $isMuted): array
    {
        return $this->transactionManager->run(function () use ($userId, $friendUserId, $isPinned, $isMuted): array {
            $friend = $this->friendOrFail($userId, $friendUserId);
            if ($isPinned !== null) {
                $friend->is_top = $isPinned ? 1 : 0;
            }
            if ($isMuted !== null) {
                $friend->is_notice = $isMuted ? 0 : 1;
            }
            $friend->update_time = time();
            $friend->save();
            $this->syncSingleConversationSettings($userId, $friendUserId, (int)$friend->is_top === 1, (int)$friend->is_notice === 0, (int)$friend->update_time);
            $directory = $this->writeContactConversationEvent($userId, $friendUserId, 'contact_settings_updated', $friend, (int)$friend->update_time);

            return [
                'user_id' => (string)$friendUserId,
                'is_pinned' => (int)$friend->is_top === 1,
                'is_muted' => (int)$friend->is_notice === 0,
                'update_time' => (int)$friend->update_time,
            ] + $directory;
        });
    }

    /**
     * 删除双向好友关系，并分别写入双方自己的用户事件日志。
     *
     * @return array<string,mixed>
     */
    public function delete(int $userId, int $friendUserId): array
    {
        return $this->transactionManager->run(function () use ($userId, $friendUserId): array {
            // 双方同时删除联系人时必须按固定顺序锁住两条关系，避免A→B与B→A形成死锁。
            $relations = AppFriendModel::query()
                ->where(static function ($query) use ($userId, $friendUserId): void {
                    $query->where(static function ($pair) use ($userId, $friendUserId): void {
                        $pair->where('create_user', $userId)->where('friend_user_id', $friendUserId);
                    })->orWhere(static function ($pair) use ($userId, $friendUserId): void {
                        $pair->where('create_user', $friendUserId)->where('friend_user_id', $userId);
                    });
                })
                ->orderBy('create_user')
                ->lockForUpdate()
                ->get();
            $friend = $relations->first(static fn (AppFriendModel $relation): bool => (
                (int)$relation->create_user === $userId
                && (int)$relation->friend_user_id === $friendUserId
            ));
            if (!$friend instanceof AppFriendModel
                || $friend->status !== FriendStatus::Friend
                || $friend->delete_time !== null
            ) {
                throw new BusinessException('CONTACT_NOT_FOUND', '联系人不存在', 404);
            }
            $now = time();
            $friend->status = FriendStatus::Deleted;
            $friend->delete_time = $now;
            $friend->update_time = $now;
            $friend->save();
            $this->hideSingleConversationMember($userId, $friendUserId, $now);
            $directory = $this->writeContactConversationEvent($userId, $friendUserId, 'contact_deleted', $friend, $now);

            $reverse = $relations->first(static fn (AppFriendModel $relation): bool => (
                (int)$relation->create_user === $friendUserId
                && (int)$relation->friend_user_id === $userId
            ));
            if ($reverse instanceof AppFriendModel) {
                $reverse->status = FriendStatus::Deleted;
                $reverse->delete_time = $now;
                $reverse->update_time = $now;
                $reverse->save();
                $this->hideSingleConversationMember($friendUserId, $userId, $now);
                $peerDirectory = $this->writeContactConversationEvent(
                    $friendUserId,
                    $userId,
                    'contact_deleted_by_peer',
                    $reverse,
                    $now,
                );
                $directory['peer_event_id'] = $peerDirectory['event']['event_id'];
            }

            return ['user_id' => (string)$friendUserId, 'relation_status' => 'deleted'] + $directory;
        });
    }

    /**
     * 拉黑用户。
     *
     * @return array<string,mixed>
     */
    public function block(int $userId, int $targetUserId): array
    {
        if ($userId === $targetUserId) {
            throw new BusinessException('VALIDATION_ERROR', '不能拉黑自己', 422);
        }
        $this->assertUserActive($targetUserId);

        return $this->transactionManager->run(function () use ($userId, $targetUserId): array {
            $now = time();
            /** @var AppFriendModel $friend */
            $friend = AppFriendModel::query()->updateOrCreate(
                ['create_user' => $userId, 'friend_user_id' => $targetUserId],
                [
                    'status' => FriendStatus::Blocked->value,
                    'delete_time' => $now,
                    'update_time' => $now,
                    'create_time' => $now,
                ],
            );
            $this->hideSingleConversationMember($userId, $targetUserId, $now);
            $directory = $this->writeContactConversationEvent($userId, $targetUserId, 'contact_blocked', $friend, $now);

            return ['user_id' => (string)$targetUserId, 'relation_status' => 'blocked'] + $directory;
        });
    }

    /**
     * 取消拉黑用户。
     *
     * @return array<string,mixed>
     */
    public function unblock(int $userId, int $targetUserId): array
    {
        return $this->transactionManager->run(function () use ($userId, $targetUserId): array {
            $friend = AppFriendModel::query()
                ->where('create_user', $userId)
                ->where('friend_user_id', $targetUserId)
                ->where('status', FriendStatus::Blocked->value)
                ->first();
            if (!$friend instanceof AppFriendModel) {
                throw new BusinessException('CONTACT_NOT_FOUND', '拉黑关系不存在', 404);
            }

            $now = time();
            $reverseFriend = $this->isFriend($targetUserId, $userId);
            $friend->status = $reverseFriend ? FriendStatus::Friend : FriendStatus::Deleted;
            $friend->delete_time = $reverseFriend ? null : $now;
            $friend->update_time = $now;
            $friend->save();
            $directory = $this->writeContactConversationEvent($userId, $targetUserId, 'contact_unblocked', $friend, $now);

            return ['user_id' => (string)$targetUserId, 'relation_status' => $friend->status->apiName()] + $directory;
        });
    }

    /**
     * 写系统通知和每个接收人的同步事件。
     *
     * @param array<int> $recipientUserIds
     * @param array<string,mixed> $payload
     */
    public function createNotification(
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
    ): AppSystemNotificationModel {
        $now = time();
        try {
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
        } catch (QueryException $exception) {
            if ($actionStatus !== NotificationActionStatus::Pending || !$this->isUniqueConstraintViolation($exception)) {
                throw $exception;
            }
            $notification = $this->pendingNotification($dedupeKey);
            if (!$notification instanceof AppSystemNotificationModel) {
                throw $exception;
            }

            return $notification;
        }

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
                $this->notificationRow($notification),
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
     * 判断数据库异常是否来自唯一约束冲突。
     */
    private function isUniqueConstraintViolation(QueryException $exception): bool
    {
        $sqlState = (string)($exception->errorInfo[0] ?? $exception->getCode());
        $driverCode = (int)($exception->errorInfo[1] ?? 0);

        return $sqlState === '23000' || $driverCode === 1062;
    }

    /**
     * 返回联系人行。
     *
     * @return array<string,mixed>
     */
    private function contactRow(int $viewerId, object $row, ?bool $isOnline): array
    {
        $name = (string)($row->nickname ?: $row->name);

        return [
            'user' => $this->userBrief($row, $isOnline),
            'remark' => $row->nickname,
            'display_name' => $name,
            'index_key' => $this->indexKey($name),
            'relation_status' => 'friend',
            'is_pinned' => (int)$row->is_top === 1,
            'is_muted' => (int)$row->is_notice === 0,
            'create_time' => (int)$row->relation_create_time,
            'update_time' => (int)$row->relation_update_time,
        ];
    }

    /**
     * 返回用户简要资料。
     *
     * @return array<string,mixed>
     */
    private function userBrief(object $user, ?bool $realtimeOnline): array
    {
        $lastActiveAt = $user->last_active_at === null ? null : (int)$user->last_active_at;
        // Centrifugo 不可用时仅对展示接口沿用旧时间窗降级，不能用于通话等业务决策。
        $isOnline = $realtimeOnline ?? ($lastActiveAt !== null && $lastActiveAt >= time() - 300);

        $username = $user->username === null ? null : (string)$user->username;

        return [
            'id' => (string)$user->user_id,
            'public_id' => (string)$user->public_id,
            'username' => $username === null ? null : '@' . $username,
            'profile_path' => $username === null ? null : $this->publicLinks->userPath($username),
            'profile_url' => $username === null ? null : $this->publicLinks->userUrl($username),
            'name' => (string)$user->name,
            'avatar_url' => $user->avatar_url ?? null,
            'verified' => (int)$user->is_auth === 1,
            'is_online' => $isOnline,
            'presence' => $isOnline ? '在线' : ($lastActiveAt === null ? '离线' : '最近曾上线'),
            'bio' => $user->motto,
            'profile_version' => (int)$user->profile_version,
        ];
    }

    /**
     * 批量查询当前页面用户在线状态。
     *
     * 展示接口优先保持可用性；Centrifugo 故障时返回空映射，
     * 由序列化逻辑使用 last_active_at 作为非强一致展示降级。
     *
     * @param list<int> $userIds 用户ID列表
     * @return array<int,bool> Centrifugo 可用时的实时在线状态
     */
    private function onlineStates(array $userIds): array
    {
        try {
            return $this->userPresence->onlineStates($userIds);
        } catch (UserPresenceUnavailableException) {
            return [];
        }
    }

    /**
     * 计算当前用户与目标用户关系。
     */
    private function relationship(int $viewerId, int $targetUserId): string
    {
        $forward = AppFriendModel::query()
            ->where('create_user', $viewerId)
            ->where('friend_user_id', $targetUserId)
            ->first();
        if ($forward instanceof AppFriendModel) {
            if ($forward->status === FriendStatus::Blocked) {
                return 'blocked';
            }
            if ($forward->status === FriendStatus::Friend && $forward->delete_time === null) {
                return 'friend';
            }
        }

        $reverseBlocked = AppFriendModel::query()
            ->where('create_user', $targetUserId)
            ->where('friend_user_id', $viewerId)
            ->where('status', FriendStatus::Blocked->value)
            ->exists();

        return $reverseBlocked ? 'blocked_by_target' : 'stranger';
    }

    /**
     * 确认目标用户可用。
     */
    private function assertUserActive(int $userId): void
    {
        $exists = AppUserModel::query()
            ->where('user_id', $userId)
            ->where('status', UserStatus::Active->value)
            ->exists();
        if (!$exists) {
            throw new BusinessException('USER_NOT_FOUND', '用户不存在或不可用', 404);
        }
    }

    /**
     * 校验可以发起好友申请。
     */
    private function assertCanRequestFriend(int $userId, int $targetUserId): void
    {
        $forward = AppFriendModel::query()
            ->where('create_user', $userId)
            ->where('friend_user_id', $targetUserId)
            ->first();
        if ($forward instanceof AppFriendModel) {
            if ($forward->status === FriendStatus::Friend && $forward->delete_time === null) {
                throw new BusinessException('FRIEND_ALREADY_EXISTS', '已是好友', 409);
            }
            if ($forward->status === FriendStatus::Blocked) {
                throw new BusinessException('FRIEND_BLOCKED_BY_ME', '当前用户已拉黑对方', 403);
            }
        }
        $reverseBlocked = AppFriendModel::query()
            ->where('create_user', $targetUserId)
            ->where('friend_user_id', $userId)
            ->where('status', FriendStatus::Blocked->value)
            ->exists();
        if ($reverseBlocked) {
            throw new BusinessException('FRIEND_BLOCKED_BY_TARGET', '对方已拉黑当前用户', 403);
        }
        if ($this->hasPendingFriendRequest($userId, $targetUserId)) {
            throw new BusinessException('FRIEND_REQUEST_PENDING', '已存在待处理好友申请', 409);
        }
    }

    /**
     * 是否已是有效好友。
     */
    private function isFriend(int $userId, int $friendUserId): bool
    {
        return AppFriendModel::query()
            ->where('create_user', $userId)
            ->where('friend_user_id', $friendUserId)
            ->where('status', FriendStatus::Friend->value)
            ->whereNull('delete_time')
            ->exists();
    }

    /**
     * 查找有效好友关系。
     */
    private function friendOrFail(int $userId, int $friendUserId): AppFriendModel
    {
        $friend = AppFriendModel::query()
            ->where('create_user', $userId)
            ->where('friend_user_id', $friendUserId)
            ->where('status', FriendStatus::Friend->value)
            ->whereNull('delete_time')
            ->first();
        if (!$friend instanceof AppFriendModel) {
            throw new BusinessException('CONTACT_NOT_FOUND', '联系人不存在', 404);
        }

        return $friend;
    }

    /**
     * 是否存在待处理好友申请。
     */
    private function hasPendingFriendRequest(int $fromUserId, int $toUserId): bool
    {
        return $this->pendingNotification('friend_request:' . $fromUserId . ':' . $toUserId) instanceof AppSystemNotificationModel;
    }

    /**
     * 根据活跃幂等键查找待处理通知。
     */
    private function pendingNotification(string $dedupeKey): ?AppSystemNotificationModel
    {
        $notification = AppSystemNotificationModel::query()
            ->where('active_dedupe_key', $dedupeKey)
            ->where('action_status', NotificationActionStatus::Pending->value)
            ->first();

        return $notification instanceof AppSystemNotificationModel ? $notification : null;
    }

    /**
     * 计算共同群数量。
     */
    private function visibleContact(int $userId, int $contactType, int $visibility, bool $isFriend): ?string
    {
        if ($visibility === 30 || ($visibility === 20 && !$isFriend)) {
            return null;
        }

        $contact = Manager::table('app_user_contact')
            ->where('user_id', $userId)
            ->where('contact_type', $contactType)
            ->first();

        return $contact?->value_masked;
    }

    /**
     * 根据隐私规则返回生日。
     */
    private function visibleBirthday(object $user, bool $isFriend): ?string
    {
        $visibility = (int)$user->birthday_visibility;
        if ($visibility === 30 || ($visibility === 20 && !$isFriend)) {
            return null;
        }

        return $user->birthday;
    }

    /**
     * 构建通知API行。
     *
     * @return array<string,mixed>
     */
    private function notificationRow(AppSystemNotificationModel $notification): array
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
            'create_time' => (int)$notification->create_time,
            'update_time' => (int)$notification->update_time,
        ];
    }

    /**
     * 同步当前用户侧单聊会话置顶和免打扰。
     */
    private function syncSingleConversationSettings(int $userId, int $friendUserId, bool $isPinned, bool $isMuted, int $now): void
    {
        $conversation = $this->singleConversation($userId, $friendUserId);
        if (!$conversation instanceof AppConversationModel) {
            return;
        }

        AppConversationMemberModel::query()
            ->where('conversation_id', (int)$conversation->conversation_id)
            ->where('user_id', $userId)
            ->update([
                'is_pinned' => $isPinned ? 1 : 0,
                'is_muted' => $isMuted ? 1 : 0,
                'update_time' => $now,
            ]);
    }

    /**
     * 隐藏当前用户侧单聊会话。
     */
    private function hideSingleConversationMember(int $userId, int $friendUserId, int $now): void
    {
        $conversation = $this->singleConversation($userId, $friendUserId);
        if (!$conversation instanceof AppConversationModel) {
            return;
        }

        AppConversationMemberModel::query()
            ->where('conversation_id', (int)$conversation->conversation_id)
            ->where('user_id', $userId)
            ->update(['is_hidden' => 1, 'update_time' => $now]);
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
     * 写联系人关系变更事件。
     */
    private function writeContactConversationEvent(int $userId, int $friendUserId, string $reason, AppFriendModel $friend, int $now): array
    {
        $conversation = $this->singleConversation($userId, $friendUserId);
        $status = $friend->status instanceof FriendStatus ? $friend->status : FriendStatus::from((int)$friend->status);
        $directoryChanges = $this->directoryProjections->contactChanges($userId, $friendUserId, $status);
        $event = $this->eventWriter->writeWithEnvelope(
            $userId,
            MessageEventType::ConversationUpdated,
            $conversation instanceof AppConversationModel ? (int)$conversation->conversation_id : null,
            null,
            [
                'reason' => $reason,
                'contact' => [
                    'user_id' => (string)$friendUserId,
                    'relation_status' => $status->apiName(),
                    'remark' => $friend->nickname,
                    'is_pinned' => (int)$friend->is_top === 1,
                    'is_muted' => (int)$friend->is_notice === 0,
                ],
                'directory_changes' => $directoryChanges,
            ],
            $now,
        );

        return [
            'event' => $event,
            // 兼容旧版联系人写接口；权威协议以event为准。
            'directory_revision' => $event['event_id'],
            'directory_changes' => $event['payload']['directory_changes'],
        ];
    }

    /**
     * 生成联系人索引字母。
     */
    private function indexKey(string $displayName): string
    {
        $latinName = transliterator_transliterate('Han-Latin; Latin-ASCII', trim($displayName));
        if (!is_string($latinName)) {
            return '#';
        }

        $first = mb_strtoupper(mb_substr(ltrim($latinName), 0, 1));

        return preg_match('/^[A-Z]$/', $first) === 1 ? $first : '#';
    }
}

<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\FriendStatus;
use app\enum\UserStatus;
use app\exception\BusinessException;
use app\model\AppMessageEventModel;
use Illuminate\Database\Capsule\Manager;

/**
 * 当前用户可见的通讯录权威投影。
 *
 * 快照不保存服务端副本：首请求固定当前用户的事件屏障，后续页把屏障放进
 * 不透明游标。快照完成后从该屏障继续增量同步，补齐分页期间发生的变化。
 */
final class ImDirectoryService
{
    private const PHASE_CONTACT = 'contact';

    /**
     * 注入目录唯一投影构造器。
     */
    public function __construct(private readonly ImDirectoryProjectionBuilder $projections)
    {
    }

    /** @return array<string,mixed> */
    public function bootstrap(int $userId, ?string $cursor, int $limit): array
    {
        $position = $cursor === null
            ? ['revision' => $this->currentRevision($userId), 'phase' => self::PHASE_CONTACT, 'after' => 0]
            : $this->decodeCursor($cursor);

        // 社区版目录只包含好友及其用户摘要；两项必须在同一页返回。
        $relationLimit = max(1, intdiv($limit + 1, 2));
        $rows = $this->contactRows($userId, $position['after'], $relationLimit);
        $items = [];
        $after = $position['after'];
        foreach ($rows as $row) {
            $brief = $this->projections->userBrief($row);
            $items[] = $this->entity('user_brief', (string)$row->user_id, $brief);
            $items[] = $this->entity('contact', (string)$row->user_id, $this->projections->contact($row, $brief));
            $after = (int)$row->friend_id;
        }
        $hasMore = count($rows) === $relationLimit;
        return $this->page(
            $position['revision'],
            $items,
            $hasMore ? $this->encodeCursor($position['revision'], self::PHASE_CONTACT, $after) : null,
            $hasMore,
        );
    }

    /** 比较好友资料版本，返回当前用户可见的变化。 */
    public function changedUserBriefs(int $viewerId, array $versions): array
    {
        if ($versions === []) {
            return [
                'items' => [],
                'barrier_event_id' => (string)$this->currentRevision($viewerId),
                'server_time' => time(),
            ];
        }
        $requested = array_column($versions, 'profile_version', 'user_id');
        $ids = array_keys($requested);
        $visible = Manager::table('app_friend')
            ->where('create_user', $viewerId)
            ->where('status', FriendStatus::Friend->value)
            ->whereNull('delete_time')
            ->whereIn('friend_user_id', $ids)
            ->pluck('friend_user_id')->map(static fn (mixed $id): int => (int)$id)->all();
        $allowed = array_values(array_unique(array_merge([$viewerId], $visible)));

        $rows = Manager::table('app_user as u')
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'u.avatar_resource')
            ->where('u.status', UserStatus::Active->value)
            ->whereIn('u.user_id', $allowed)
            ->whereIn('u.user_id', $ids)
            ->select(['u.user_id', 'u.public_id', 'u.username', 'u.name', 'u.motto', 'u.is_auth', 'u.profile_version', 'u.last_active_at', 'avatar.src as avatar_url'])
            ->get();
        $items = [];
        foreach ($rows as $row) {
            if ((int)$row->profile_version !== (int)$requested[(int)$row->user_id]) {
                $items[] = $this->projections->userBrief($row);
            }
        }

        return [
            'items' => $items,
            'barrier_event_id' => (string)$this->currentRevision($viewerId),
            'server_time' => time(),
        ];
    }

    /** @return list<object> */
    private function contactRows(int $userId, int $after, int $limit): array
    {
        return Manager::table('app_friend as f')
            ->join('app_user as u', 'u.user_id', '=', 'f.friend_user_id')
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'u.avatar_resource')
            ->where('f.create_user', $userId)
            ->where('f.status', FriendStatus::Friend->value)
            ->whereNull('f.delete_time')
            ->where('u.status', UserStatus::Active->value)
            ->where('f.friend_id', '>', $after)
            ->orderBy('f.friend_id')
            ->limit($limit)
            ->select(['f.friend_id', 'f.status as relation_status', 'f.nickname', 'f.is_top', 'f.is_notice', 'f.create_time as relation_create_time', 'f.update_time as relation_update_time', 'u.user_id', 'u.public_id', 'u.username', 'u.name', 'u.motto', 'u.is_auth', 'u.profile_version', 'u.last_active_at', 'avatar.src as avatar_url'])
            ->get()->all();
    }

    /** @return list<object> */
    private function entity(string $type, string $key, array $data): array
    {
        return ['entity_type' => $type, 'entity_key' => $key, 'data' => $data];
    }

    /** @param list<array<string,mixed>> $items @return array<string,mixed> */
    private function page(int $revision, array $items, ?string $cursor, bool $hasMore): array
    {
        return ['barrier_event_id' => (string)$revision, 'items' => $items, 'next_cursor' => $cursor, 'has_more' => $hasMore, 'server_time' => time()];
    }

    /**
     * 返回当前用户已经存在的最大事件ID，作为Bootstrap后的增量追赶起点。
     */
    private function currentRevision(int $userId): int
    {
        return (int)(AppMessageEventModel::query()
            ->where('user_id', $userId)
            ->max('event_id') ?? 0);
    }

    /**
     * 编码固定事件屏障和Keyset位置的不透明目录游标。
     */
    private function encodeCursor(int $revision, string $phase, int $after): string
    {
        return rtrim(strtr(base64_encode(json_encode(['r' => $revision, 'p' => $phase, 'a' => $after], JSON_THROW_ON_ERROR)), '+/', '-_'), '=');
    }

    /** @return array{revision:int,phase:string,after:int} */
    private function decodeCursor(string $cursor): array
    {
        $decoded = base64_decode(strtr($cursor, '-_', '+/'), true);
        $value = $decoded === false ? null : json_decode($decoded, true);
        if (!is_array($value) || !isset($value['r'], $value['p'], $value['a'])
            || !in_array($value['p'], [self::PHASE_CONTACT], true)
            || !is_int($value['r']) || !is_int($value['a']) || $value['r'] < 0 || $value['a'] < 0
        ) {
            throw new BusinessException('DIRECTORY_CURSOR_INVALID', '目录游标无效，请重新执行全量校准', 409);
        }
        return ['revision' => $value['r'], 'phase' => $value['p'], 'after' => $value['a']];
    }

}

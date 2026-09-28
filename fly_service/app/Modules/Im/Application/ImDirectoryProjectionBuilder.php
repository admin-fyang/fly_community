<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\FriendStatus;
use app\Support\Link\PublicLinkService;
use Illuminate\Database\Capsule\Manager;

/**
 * IM目录客户端投影的唯一构造器。
 *
 * Bootstrap、HTTP写穿和实时事件必须复用本类，避免同一实体在不同链路出现字段漂移。
 */
final class ImDirectoryProjectionBuilder
{
    /**
     * 注入公开链接构造能力。
     */
    public function __construct(private readonly PublicLinkService $publicLinks)
    {
    }

    /**
     * 构造联系人目录变化；删除关系只返回墓碑。
     *
     * @return list<array<string,mixed>>
     */
    public function contactChanges(int $viewerId, int $targetUserId, FriendStatus $status): array
    {
        if ($status === FriendStatus::Deleted) {
            return [$this->deleteChange('contact', (string)$targetUserId)];
        }

        $row = Manager::table('app_friend as f')
            ->join('app_user as u', 'u.user_id', '=', 'f.friend_user_id')
            ->leftJoin('app_file as avatar', 'avatar.resource_id', '=', 'u.avatar_resource')
            ->where('f.create_user', $viewerId)
            ->where('f.friend_user_id', $targetUserId)
            ->select([
                'f.status as relation_status', 'f.nickname', 'f.is_top', 'f.is_notice',
                'f.create_time as relation_create_time', 'f.update_time as relation_update_time',
                'u.user_id', 'u.public_id', 'u.username', 'u.name', 'u.motto', 'u.is_auth',
                'u.profile_version', 'u.last_active_at', 'avatar.src as avatar_url',
            ])->first();
        if ($row === null) {
            return [$this->deleteChange('contact', (string)$targetUserId)];
        }

        $brief = $this->userBrief($row);
        $contact = $this->contact($row, $brief);
        $contact['relation_status'] = $status->apiName();

        return [
            $this->upsertChange('user_brief', (string)$targetUserId, $brief),
            $this->upsertChange('contact', (string)$targetUserId, $contact),
        ];
    }

    /**
     * 构造联系人目录投影。
     *
     * @param array<string,mixed> $brief 用户公开摘要
     * @return array<string,mixed>
     */
    public function contact(object $row, array $brief): array
    {
        $displayName = (string)($row->nickname ?: $row->name);
        return [
            'user' => $brief,
            'remark' => $row->nickname,
            'display_name' => $displayName,
            'index_key' => $this->indexKey($displayName),
            'relation_status' => FriendStatus::from((int)$row->relation_status)->apiName(),
            'is_pinned' => (int)$row->is_top === 1,
            'is_muted' => (int)$row->is_notice === 0,
            'create_time' => (int)$row->relation_create_time,
            'update_time' => (int)$row->relation_update_time,
        ];
    }

    /**
     * 将已查询用户行转换为统一公开摘要。
     *
     * @return array<string,mixed>
     */
    public function userBrief(object $row): array
    {
        $username = $row->username === null ? null : (string)$row->username;
        return [
            'id' => (string)$row->user_id,
            'public_id' => (string)$row->public_id,
            'username' => $username === null ? null : '@' . $username,
            'profile_path' => $username === null ? null : $this->publicLinks->userPath($username),
            'profile_url' => $username === null ? null : $this->publicLinks->userUrl($username),
            'name' => (string)$row->name,
            'avatar_url' => $row->avatar_url ?? null,
            'verified' => (int)$row->is_auth === 1,
            'bio' => $row->motto,
            'profile_version' => (int)$row->profile_version,
            'last_active_at' => isset($row->last_active_at) ? (int)$row->last_active_at : null,
        ];
    }

    /**
     * 构造目录更新事件。
     *
     * @return array<string,mixed>
     */
    private function upsertChange(string $type, string $key, array $data): array
    {
        return ['entity_type' => $type, 'entity_key' => $key, 'operation' => 'upsert', 'data' => $data];
    }

    /** @return array<string,mixed> */
    private function deleteChange(string $type, string $key): array
    {
        return ['entity_type' => $type, 'entity_key' => $key, 'operation' => 'delete'];
    }

    /** @return array<string,mixed> */
    private function invalidateScopeChange(string $type, string $key): array
    {
        return ['entity_type' => $type, 'entity_key' => $key, 'operation' => 'invalidate_scope'];
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

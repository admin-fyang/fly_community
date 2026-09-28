<?php

declare(strict_types=1);

namespace app\Modules\Account\Application;

use app\exception\BusinessException;
use app\model\AppUserSessionModel;
use app\Modules\Account\Domain\Repository\SessionSnapshotStore;
use app\Support\Auth\AuthContext;

/** 按登录会话查询设备列表；冻结排序，仅从数据库确认当前仍有效的记录。 */
final class DeviceSessionService
{
    /** 注入短期快照及单快照容量上限，防止异常账号耗尽 Worker 内存。 */
    public function __construct(private readonly SessionSnapshotStore $snapshots, private readonly int $maxSessions)
    {
    }

    /** 当前会话单独返回；扫描位置而非存活条数驱动游标，删除/过期不会造成循环。 */
    public function listing(AuthContext $auth, int $limit, ?string $cursor): array
    {
        $this->snapshots->assertAllowed($auth->userId);
        $now = time();
        $current = AppUserSessionModel::query()->whereKey($auth->sessionId)->where('user_id', $auth->userId)
            ->whereNull('revoked_at')->where('expires_at', '>', $now)->first();
        if ($current === null) {
            throw new BusinessException('AUTH_SESSION_REVOKED', '此设备已被退出，请重新登录', 401);
        }
        if ($cursor === null) {
            $ids = AppUserSessionModel::query()->where('user_id', $auth->userId)->where('session_id', '<>', $auth->sessionId)
                ->whereNull('revoked_at')->where('expires_at', '>', $now)
                ->orderByDesc('last_active_at')->orderByDesc('session_id')->limit($this->maxSessions + 1)->pluck('session_id')->all();
            if (count($ids) > $this->maxSessions) {
                throw new BusinessException('AUTH_SESSION_SERVICE_UNAVAILABLE', '登录会话数量超出查询容量，请联系管理员', 503);
            }
            $snapshot = ['user_id' => $auth->userId, 'session_id' => $auth->sessionId, 'ids' => $ids, 'secret' => bin2hex(random_bytes(32))];
            $id = $this->snapshots->create($snapshot);
            $position = 0;
        } else {
            [$id, $position, $snapshot] = $this->decode($auth, $cursor);
        }
        $items = [];
        $ids = $snapshot['ids'];
        // 每轮批量查询而非逐条 SELECT；记录在快照后撤销时跳过并继续补满本页。
        while ($position < count($ids) && count($items) < $limit) {
            $batch = array_slice($ids, $position, min(100, count($ids) - $position));
            $rows = AppUserSessionModel::query()->where('user_id', $auth->userId)->whereIn('session_id', $batch)
                ->whereNull('revoked_at')->where('expires_at', '>', $now)->get()->keyBy('session_id');
            foreach ($batch as $sessionId) {
                ++$position;
                if (isset($rows[$sessionId])) {
                    $items[] = $this->present($rows[$sessionId]);
                }
                if (count($items) === $limit) {
                    break;
                }
            }
        }
        return ['current_session' => $this->present($current), 'items' => $items,
            'next_cursor' => $position < count($ids) ? $this->encode($id, $position, $snapshot['secret']) : null];
    }

    /** 校验签名与快照身份，不允许修改位置或跨用户/跨当前会话复用。 */
    private function decode(AuthContext $auth, string $cursor): array
    {
        if (preg_match('/^([0-9a-f]{32})\.([0-9]{1,8})\.([0-9a-f]{64})$/D', $cursor, $parts) === 1) {
            $snapshot = $this->snapshots->find($parts[1]);
            $position = (int)$parts[2];
            if ($snapshot !== null && $snapshot['user_id'] === $auth->userId && $snapshot['session_id'] === $auth->sessionId
                && $position > 0 && $position < count($snapshot['ids'])
                && hash_equals($this->encode($parts[1], $position, $snapshot['secret']), $cursor)) {
                return [$parts[1], $position, $snapshot];
            }
        }
        throw new BusinessException('AUTH_SESSION_CURSOR_INVALID', '设备列表已失效，请刷新后重试', 400);
    }

    /** 同一快照位置生成相同游标，客户端重试同一页不会产生新的分页链。 */
    private function encode(string $id, int $position, string $secret): string
    {
        $payload = $id . '.' . $position;
        return $payload . '.' . hash_hmac('sha256', $payload, $secret);
    }

    /** 白名单输出会话创建时资料，不读取可被重新登录覆盖的设备主档名称。 */
    private function present(AppUserSessionModel $session): array
    {
        return ['session_id' => (string)$session->session_id, 'device_id' => (string)$session->device_id,
            'device_name' => $session->device_name, 'platform' => $session->platform, 'app_version' => $session->app_version,
            'created_at' => $session->created_at, 'last_active_at' => $session->last_active_at, 'login_ip' => $session->login_ip];
    }
}

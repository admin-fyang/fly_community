<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Redis;

use app\exception\BusinessException;
use app\Modules\Account\Domain\Repository\SessionSnapshotStore;
use Predis\Client;
use Throwable;

/** 多 Worker 共用的 Redis 会话快照与限流；Redis 故障不降级为不稳定分页。 */
final class RedisSessionSnapshotStore implements SessionSnapshotStore
{
    /** 注入 Redis、快照有效期和用户分钟请求额度。 */
    public function __construct(private readonly Client $redis, private readonly int $ttl, private readonly int $requestLimit)
    {
    }

    /** 快照 ID 和签名材料均不可预测，TTL 不随翻页延长。 */
    public function create(array $snapshot): string
    {
        $id = bin2hex(random_bytes(16));
        try {
            $this->redis->setex('auth:sessions:snapshot:' . $id, $this->ttl, json_encode($snapshot, JSON_THROW_ON_ERROR));
        } catch (Throwable) {
            throw new BusinessException('AUTH_SESSION_SERVICE_UNAVAILABLE', '设备列表暂时不可用，请稍后重试', 503);
        }
        return $id;
    }

    /** 仅返回服务端保存的快照，禁止从客户端载荷恢复列表事实。 */
    public function find(string $id): ?array
    {
        try {
            $value = $this->redis->get('auth:sessions:snapshot:' . $id);
            return $value === null ? null : json_decode($value, true, 512, JSON_THROW_ON_ERROR);
        } catch (Throwable) {
            throw new BusinessException('AUTH_SESSION_SERVICE_UNAVAILABLE', '设备列表暂时不可用，请稍后重试', 503);
        }
    }

    /** Lua 原子设置首次计数的过期时间，避免进程退出留下永久限流键。 */
    public function assertAllowed(int $userId): void
    {
        try {
            $count = (int)$this->redis->eval(
                "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],60) end; return n",
                1,
                'auth:sessions:limit:' . $userId,
            );
        } catch (Throwable) {
            throw new BusinessException('AUTH_SESSION_SERVICE_UNAVAILABLE', '设备管理暂时不可用，请稍后重试', 503);
        }
        if ($count > $this->requestLimit) {
            throw new BusinessException('TOO_MANY_REQUESTS', '操作过于频繁，请稍后重试', 429);
        }
    }
}

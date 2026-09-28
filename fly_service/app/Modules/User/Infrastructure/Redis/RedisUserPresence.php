<?php

declare(strict_types=1);

namespace app\Modules\User\Infrastructure\Redis;

use app\Modules\User\Domain\Exception\UserPresenceUnavailableException;
use app\Modules\User\Domain\Service\UserPresence;
use Predis\Client;
use Throwable;

/**
 * 读取Presence Listener维护的Redis在线状态。
 */
final class RedisUserPresence implements UserPresence
{
    /**
     * 注入Redis客户端和Listener健康状态最大陈旧时间。
     */
    public function __construct(
        private readonly Client $redis,
        private readonly int $listenerStaleSeconds,
    ) {
    }

    /**
     * 判断用户是否至少有一个Centrifugo连接。
     */
    public function isOnline(int $userId): bool
    {
        $this->assertHealthy();
        try {
            return (int)$this->redis->scard($this->userClientsKey($userId)) > 0;
        } catch (Throwable) {
            throw new UserPresenceUnavailableException('presence_redis_unavailable');
        }
    }

    /**
     * 判断指定安装实例是否至少有一个Centrifugo连接。
     */
    public function isDeviceOnline(int $userId, string $deviceId): bool
    {
        $this->assertHealthy();
        try {
            return (int)$this->redis->scard($this->deviceClientsKey($userId, $deviceId)) > 0;
        } catch (Throwable) {
            throw new UserPresenceUnavailableException('presence_redis_unavailable');
        }
    }

    /**
     * 批量读取用户状态；使用Pipeline避免联系人或群成员列表逐用户访问Redis。
     *
     * @param list<int> $userIds
     * @return array<int,bool>
     */
    public function onlineStates(array $userIds): array
    {
        $this->assertHealthy();
        $ids = array_values(array_unique(array_map('intval', $userIds)));
        if ($ids === []) {
            return [];
        }
        try {
            $counts = $this->redis->pipeline(function ($pipe) use ($ids): void {
                foreach ($ids as $userId) {
                    $pipe->scard($this->userClientsKey($userId));
                }
            });
        } catch (Throwable) {
            throw new UserPresenceUnavailableException('presence_redis_unavailable');
        }
        $result = [];
        foreach ($ids as $index => $userId) {
            $result[$userId] = (int)($counts[$index] ?? 0) > 0;
        }
        return $result;
    }

    /**
     * Listener失联时状态可能漂移，必须向调用方显式报告而不能误判为离线。
     */
    private function assertHealthy(): void
    {
        try {
            $lastReconcileAt = (int)($this->redis->get('im:presence:listener:last_reconcile_at') ?? 0);
            $rawStatus = $this->redis->get('im:presence:listener:status');
        } catch (Throwable) {
            throw new UserPresenceUnavailableException('presence_redis_unavailable');
        }
        $status = is_string($rawStatus) ? json_decode($rawStatus, true) : null;
        if ($lastReconcileAt <= 0
            || !is_array($status)
            || ($status['state'] ?? null) !== 'healthy'
            || (int)($status['updated_at'] ?? 0) < time() - $this->listenerStaleSeconds) {
            throw new UserPresenceUnavailableException('presence_listener_degraded');
        }
    }

    /** 返回用户连接集合键。 */
    private function userClientsKey(int $userId): string
    {
        return 'im:presence:user:' . $userId . ':clients';
    }

    /** 返回用户设备连接集合键。 */
    private function deviceClientsKey(int $userId, string $deviceId): string
    {
        return 'im:presence:user:' . $userId . ':device:' . strtolower($deviceId) . ':clients';
    }
}

<?php

declare(strict_types=1);

namespace app\Modules\User\Domain\Service;

use app\Modules\User\Domain\Exception\UserPresenceUnavailableException;

/**
 * 用户实时在线状态查询边界。
 *
 * 在线只表示用户至少有一个设备保持 Centrifugo Presence 分片订阅，
 * 不表示用户正在操作应用，也不替代持久化的最后活跃时间。
 */
interface UserPresence
{
    /**
     * 判断指定用户是否至少有一个实时连接。
     *
     * @throws UserPresenceUnavailableException Listener 或 Redis 健康状态不可用时抛出
     */
    public function isOnline(int $userId): bool;

    /**
     * 判断指定安装实例是否至少有一个实时连接，供FCM按设备分流。
     *
     * @throws UserPresenceUnavailableException Listener或Redis状态不可用时抛出
     */
    public function isDeviceOnline(int $userId, string $deviceId): bool;

    /**
     * 批量查询用户实时在线状态，避免列表接口逐用户发起网络请求。
     *
     * @param list<int> $userIds 用户ID列表
     * @return array<int,bool> 以用户ID为键的在线状态
     *
     * @throws UserPresenceUnavailableException Listener 或 Redis 健康状态不可用时抛出
     */
    public function onlineStates(array $userIds): array;
}

<?php

declare(strict_types=1);

namespace app\Modules\Im\Domain\Service;

/**
 * Centrifugo连接Token签发边界。
 */
interface CentrifugoTokenIssuer
{
    /**
     * 为当前用户和设备签发个人频道及后端指定Presence分片的短期连接Token。
     */
    public function issue(int $userId, string $deviceId, string $sessionId, int $now): string;

    /**
     * 返回连接Token有效秒数。
     */
    public function ttlSeconds(): int;
}

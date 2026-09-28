<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Service;

interface AccessTokenIssuer
{
    /**
     * 为指定用户、会话和设备签发短期Access Token。
     */
    public function issue(int $userId, string $sessionId, string $deviceId, int $now): string;

    /**
     * 返回Access Token有效秒数。
     */
    public function ttlSeconds(): int;
}

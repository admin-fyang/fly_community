<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\DTO;

/**
 * 已持久化的新会话及客户端需要收到的 Refresh Token。
 */
final readonly class CreatedSession
{
    /**
     * 创建已持久化会话的返回数据。
     */
    public function __construct(
        public string $sessionId,
        public string $refreshToken,
        public int $refreshExpiresIn,
    ) {
    }
}

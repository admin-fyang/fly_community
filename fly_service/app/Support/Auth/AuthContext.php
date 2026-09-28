<?php

declare(strict_types=1);

namespace app\Support\Auth;

/**
 * 当前请求已认证的用户、会话和设备上下文。
 */
final readonly class AuthContext
{
    /**
     * 保存服务端验证后的认证身份。
     */
    public function __construct(
        public int $userId,
        public string $sessionId,
        public string $deviceId,
    ) {
    }
}

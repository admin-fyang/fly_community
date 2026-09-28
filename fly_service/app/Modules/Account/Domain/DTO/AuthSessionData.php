<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\DTO;

/**
 * 注册或登录成功后的认证结果。
 */
final readonly class AuthSessionData
{
    /**
     * @param array<string, mixed> $user
     */
    public function __construct(
        public string $accessToken,
        public int $accessTokenExpiresIn,
        public string $refreshToken,
        public int $refreshTokenExpiresIn,
        public string $sessionId,
        public array $user,
    ) {
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'access_token' => $this->accessToken,
            'access_token_expires_in' => $this->accessTokenExpiresIn,
            'refresh_token' => $this->refreshToken,
            'refresh_token_expires_in' => $this->refreshTokenExpiresIn,
            'session_id' => $this->sessionId,
            'user' => $this->user,
        ];
    }
}

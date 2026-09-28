<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Security;

use app\Support\Id\IdGenerator;
use RuntimeException;

/**
 * 创建仅向客户端展示一次的 Refresh Token 及其服务端 HMAC。
 */
final class RefreshTokenFactory
{
    private readonly string $key;

    /**
     * 注入ID生成器、Refresh Token专用密钥及有效期。
     */
    public function __construct(
        private readonly IdGenerator $ids,
        string $keyBase64,
        private readonly int $ttlSeconds,
    ) {
        $key = base64_decode($keyBase64, true);
        if ($key === false || strlen($key) !== 32) {
            throw new RuntimeException('AUTH_REFRESH_TOKEN_KEY 必须是 Base64 编码的 32 字节密钥');
        }
        $this->key = $key;
    }

    /**
     * @return array{token_id:string,token:string,hash:string,expires_in:int}
     */
    public function create(string $sessionId): array
    {
        $tokenId = $this->ids->uuidV4();
        $secret = rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
        $token = $sessionId . '.' . $tokenId . '.' . $secret;

        return [
            'token_id' => $tokenId,
            'token' => $token,
            'hash' => hash_hmac('sha256', $token, $this->key, true),
            'expires_in' => $this->ttlSeconds,
        ];
    }

    /** 校验凭证时复用同一用途密钥，明文只在当前请求内存中存在。 */
    public function hash(string $token): string
    {
        return hash_hmac('sha256', $token, $this->key, true);
    }
}

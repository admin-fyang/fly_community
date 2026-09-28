<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Security;

use app\Modules\Account\Domain\Service\AccessTokenIssuer;
use app\Support\Id\IdGenerator;
use Firebase\JWT\JWT;
use RuntimeException;

/**
 * 使用 Ed25519 签发不含 PII 的短期 JWT。
 */
final class EdDsaJwtAccessTokenIssuer implements AccessTokenIssuer
{
    /**
     * 注入签名配置并校验Ed25519私钥长度。
     */
    public function __construct(
        private readonly IdGenerator $ids,
        private readonly string $privateKey,
        private readonly string $keyId,
        private readonly string $issuer,
        private readonly string $audience,
        private readonly int $ttl,
    ) {
        $decoded = base64_decode($privateKey, true);
        if ($decoded === false || strlen($decoded) !== SODIUM_CRYPTO_SIGN_SECRETKEYBYTES) {
            throw new RuntimeException('AUTH_JWT_PRIVATE_KEY 必须是 Base64 编码的 Ed25519 私钥');
        }
    }

    /**
     * 签发只包含身份、会话和设备标识的EdDSA JWT。
     */
    public function issue(int $userId, string $sessionId, string $deviceId, int $now): string
    {
        return JWT::encode([
            'iss' => $this->issuer,
            'aud' => $this->audience,
            'sub' => (string) $userId,
            'sid' => $sessionId,
            'did' => $deviceId,
            'iat' => $now,
            'nbf' => $now,
            'exp' => $now + $this->ttl,
            'jti' => $this->ids->uuidV4(),
        ], $this->privateKey, 'EdDSA', $this->keyId);
    }

    /**
     * 返回Access Token配置的有效秒数。
     */
    public function ttlSeconds(): int
    {
        return $this->ttl;
    }
}

<?php

declare(strict_types=1);

namespace app\Modules\Im\Infrastructure\Security;

use app\exception\BusinessException;
use app\Modules\Im\Domain\Service\CentrifugoTokenIssuer;
use Firebase\JWT\JWT;
use app\Modules\User\Domain\Service\PresenceShard;

/**
 * 使用HS256签发Centrifugo连接Token。
 */
final class HmacCentrifugoTokenIssuer implements CentrifugoTokenIssuer
{
    /**
     * 注入Centrifugo Token配置。
     */
    public function __construct(
        private readonly bool $enabled,
        private readonly string $secret,
        private readonly int $ttl,
        private readonly int $presenceShardCount,
    ) {
    }

    /**
     * 为当前用户和设备签发短期连接Token。
     */
    public function issue(int $userId, string $deviceId, string $sessionId, int $now): string
    {
        if (!$this->enabled || strlen($this->secret) < 32) {
            throw new BusinessException(
                'IM_CENTRIFUGO_TOKEN_FAILED',
                '实时消息服务尚未正确配置',
                503,
            );
        }

        return JWT::encode([
            'sub' => (string)$userId,
            'iat' => $now,
            'exp' => $now + $this->ttl,
            'info' => [
                'user_id' => (string)$userId,
                'device_id' => $deviceId,
                'session_id' => $sessionId,
            ],
            // 两类频道必须统一放入subs。Centrifugo同时收到channels与subs时，线上实际只建立了
            // subs内的Presence订阅，导致private-user频道无人订阅、消息与通话邀请实时投递失效。
            'subs' => [
                'private-user:' . $userId => (object)[],
                // Presence频道由签名JWT建立服务端订阅，普通客户端不能选择分片或接收Join/Leave。
                PresenceShard::channel($userId, $this->presenceShardCount) => (object)[],
            ],
        ], $this->secret, 'HS256');
    }

    /**
     * 返回连接Token有效秒数。
     */
    public function ttlSeconds(): int
    {
        return $this->ttl;
    }
}

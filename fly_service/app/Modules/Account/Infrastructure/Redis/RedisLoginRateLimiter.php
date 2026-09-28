<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Redis;

use app\Modules\Account\Domain\Repository\LoginRateLimiter;
use app\exception\BusinessException;
use Predis\Client;

/**
 * 按“身份+IP”和身份全局两个维度限制密码爆破。
 */
final class RedisLoginRateLimiter implements LoginRateLimiter
{
    private const FAILURE_SCRIPT = <<<'LUA'
local pair = redis.call('INCR', KEYS[1])
if pair == 1 then redis.call('EXPIRE', KEYS[1], 900) end
local identity = redis.call('INCR', KEYS[2])
if identity == 1 then redis.call('EXPIRE', KEYS[2], 3600) end
return {pair, identity}
LUA;

    /**
     * 注入当前Worker复用的Redis客户端。
     */
    public function __construct(private readonly Client $redis)
    {
    }

    /**
     * 检查组合维度和身份全局维度是否达到失败阈值。
     */
    public function assertAllowed(string $identityHash, string $ipHash): void
    {
        $pair = (int) ($this->redis->get($this->pairKey($identityHash, $ipHash)) ?? 0);
        $identity = (int) ($this->redis->get($this->identityKey($identityHash)) ?? 0);
        if ($pair >= 5 || $identity >= 20) {
            throw new BusinessException('AUTH_TOO_MANY_ATTEMPTS', '登录尝试过多，请稍后再试', 429);
        }
    }

    /**
     * 通过Lua原子增加两个维度的失败次数。
     */
    public function recordFailure(string $identityHash, string $ipHash): void
    {
        $this->redis->eval(
            self::FAILURE_SCRIPT,
            2,
            $this->pairKey($identityHash, $ipHash),
            $this->identityKey($identityHash),
        );
    }

    /**
     * 登录成功后删除两个维度的失败状态。
     */
    public function clear(string $identityHash, string $ipHash): void
    {
        $this->redis->del(
            $this->pairKey($identityHash, $ipHash),
            $this->identityKey($identityHash),
        );
    }

    /**
     * 生成身份与IP组合限流键。
     */
    private function pairKey(string $identityHash, string $ipHash): string
    {
        return "auth:limit:login:pair:{$identityHash}:{$ipHash}";
    }

    /**
     * 生成身份全局限流键。
     */
    private function identityKey(string $identityHash): string
    {
        return "auth:limit:login:identity:{$identityHash}";
    }
}

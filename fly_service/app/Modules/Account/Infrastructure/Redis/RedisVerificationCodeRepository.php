<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Redis;

use app\Modules\Account\Domain\DTO\VerificationCodeClaim;
use app\Modules\Account\Domain\Enum\VerificationScene;
use app\Modules\Account\Domain\Repository\VerificationCodeRepository;
use app\exception\BusinessException;
use Predis\Client;
use RuntimeException;

/**
 * 使用 Lua 原子维护验证码状态和发送频率。
 */
final class RedisVerificationCodeRepository implements VerificationCodeRepository
{
    private const RESERVE_SCRIPT = <<<'LUA'
if redis.call('EXISTS', KEYS[2]) == 1 then return -1 end
if tonumber(redis.call('GET', KEYS[3]) or '0') >= 5 then return -2 end
if tonumber(redis.call('GET', KEYS[4]) or '0') >= 10 then return -3 end
if tonumber(redis.call('GET', KEYS[5]) or '0') >= 20 then return -4 end
redis.call('HSET', KEYS[1],
  'scene', ARGV[1],
  'target_hash', ARGV[2],
  'code_hash', ARGV[3],
  'attempts', '0',
  'state', 'pending')
redis.call('EXPIRE', KEYS[1], tonumber(ARGV[4]))
redis.call('SET', KEYS[2], ARGV[5], 'EX', tonumber(ARGV[6]))
local hourTarget = redis.call('INCR', KEYS[3])
if hourTarget == 1 then redis.call('EXPIRE', KEYS[3], 3600) end
local dayTarget = redis.call('INCR', KEYS[4])
if dayTarget == 1 then redis.call('EXPIRE', KEYS[4], 86400) end
local hourIp = redis.call('INCR', KEYS[5])
if hourIp == 1 then redis.call('EXPIRE', KEYS[5], 3600) end
return 1
LUA;

    private const ACTIVATE_SCRIPT = <<<'LUA'
if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
if redis.call('HGET', KEYS[1], 'state') ~= 'pending' then return -1 end
redis.call('HSET', KEYS[1], 'state', 'active')
return 1
LUA;

    private const CANCEL_SCRIPT = <<<'LUA'
redis.call('DEL', KEYS[1])
if redis.call('GET', KEYS[2]) == ARGV[1] then redis.call('DEL', KEYS[2]) end
return 1
LUA;

    private const CONSUME_SCRIPT = <<<'LUA'
if redis.call('EXISTS', KEYS[1]) == 0 then return -1 end
local state = redis.call('HGET', KEYS[1], 'state')
if state == 'consumed' then return -2 end
if state ~= 'active' then return -3 end
if redis.call('HGET', KEYS[1], 'scene') ~= ARGV[1] then return -4 end
if redis.call('HGET', KEYS[1], 'target_hash') ~= ARGV[2] then return -4 end
if redis.call('HGET', KEYS[1], 'code_hash') ~= ARGV[3] then
  local attempts = redis.call('HINCRBY', KEYS[1], 'attempts', 1)
  if attempts >= tonumber(ARGV[4]) then redis.call('DEL', KEYS[1]) end
  return -5
end
redis.call('HSET', KEYS[1], 'state', 'consumed')
redis.call('EXPIRE', KEYS[1], 60)
return 1
LUA;

    /**
     * 先完整校验全部验证码，再统一标记为已消费，避免双验证注册出现半消费状态。
     */
    private const CONSUME_ALL_SCRIPT = <<<'LUA'
local count = tonumber(ARGV[1])
local maxAttempts = tonumber(ARGV[2])
for index = 1, count do
  local key = KEYS[index]
  local offset = 2 + ((index - 1) * 3)
  if redis.call('EXISTS', key) == 0 then return -1 end
  local state = redis.call('HGET', key, 'state')
  if state == 'consumed' then return -2 end
  if state ~= 'active' then return -3 end
  if redis.call('HGET', key, 'scene') ~= ARGV[offset + 1] then return -4 end
  if redis.call('HGET', key, 'target_hash') ~= ARGV[offset + 2] then return -4 end
  if redis.call('HGET', key, 'code_hash') ~= ARGV[offset + 3] then
    local attempts = redis.call('HINCRBY', key, 'attempts', 1)
    if attempts >= maxAttempts then redis.call('DEL', key) end
    return -5
  end
end
for index = 1, count do
  redis.call('HSET', KEYS[index], 'state', 'consumed')
  redis.call('EXPIRE', KEYS[index], 60)
end
return 1
LUA;

    /**
     * 注入当前Worker复用的Redis客户端。
     */
    public function __construct(private readonly Client $redis)
    {
    }

    /**
     * 原子创建待发送验证码并增加目标与IP频率计数。
     */
    public function reserve(
        string $requestId,
        VerificationScene $scene,
        string $targetHash,
        string $codeHash,
        string $ipHash,
        int $ttlSeconds,
        int $resendSeconds,
    ): void {
        $now = time();
        $result = (int) $this->redis->eval(
            self::RESERVE_SCRIPT,
            5,
            $this->requestKey($requestId),
            "auth:verify:target:{$scene->value}:{$targetHash}",
            "auth:limit:send:target:{$targetHash}:hour:" . intdiv($now, 3600),
            "auth:limit:send:target:{$targetHash}:day:" . intdiv($now, 86400),
            "auth:limit:send:ip:{$ipHash}:hour:" . intdiv($now, 3600),
            $scene->value,
            $targetHash,
            $codeHash,
            (string) $ttlSeconds,
            $requestId,
            (string) $resendSeconds,
        );

        if ($result !== 1) {
            throw new BusinessException('VERIFY_SEND_TOO_FREQUENT', '验证码发送过于频繁', 429);
        }
    }

    /**
     * 将供应商发送成功的验证码切换为可校验状态。
     */
    public function activate(string $requestId): void
    {
        $result = (int) $this->redis->eval(self::ACTIVATE_SCRIPT, 1, $this->requestKey($requestId));
        if ($result !== 1) {
            throw new RuntimeException('验证码状态激活失败');
        }
    }

    /**
     * 删除发送失败的验证码并释放短期目标占用。
     */
    public function cancel(string $requestId, VerificationScene $scene, string $targetHash): void
    {
        $this->redis->eval(
            self::CANCEL_SCRIPT,
            2,
            $this->requestKey($requestId),
            "auth:verify:target:{$scene->value}:{$targetHash}",
            $requestId,
        );
    }

    /**
     * 原子检查场景、目标、验证码和失败次数后消费验证码。
     */
    public function consume(
        string $requestId,
        VerificationScene $scene,
        string $targetHash,
        string $codeHash,
        int $maxAttempts,
    ): void {
        $result = (int) $this->redis->eval(
            self::CONSUME_SCRIPT,
            1,
            $this->requestKey($requestId),
            $scene->value,
            $targetHash,
            $codeHash,
            (string) $maxAttempts,
        );

        match ($result) {
            1 => null,
            -1 => throw new BusinessException('VERIFY_CODE_EXPIRED', '验证码已过期', 410),
            -2 => throw new BusinessException('VERIFY_CODE_CONSUMED', '验证码已使用', 410),
            -5 => throw new BusinessException('VERIFY_CODE_INVALID', '验证码不正确', 422),
            default => throw new BusinessException('VERIFY_CODE_INVALID', '验证码不正确', 422),
        };
    }

    /**
     * 在同一段 Lua 中原子消费注册所需的全部验证码。
     *
     * @param list<VerificationCodeClaim> $claims
     */
    public function consumeAll(array $claims, int $maxAttempts): void
    {
        if ($claims === []) {
            return;
        }

        $keys = [];
        $arguments = [(string) count($claims), (string) $maxAttempts];
        foreach ($claims as $claim) {
            $keys[] = $this->requestKey($claim->requestId);
            $arguments[] = $claim->scene->value;
            $arguments[] = $claim->targetHash;
            $arguments[] = $claim->codeHash;
        }

        $result = (int) $this->redis->eval(
            self::CONSUME_ALL_SCRIPT,
            count($keys),
            ...$keys,
            ...$arguments,
        );

        match ($result) {
            1 => null,
            -1 => throw new BusinessException('VERIFY_CODE_EXPIRED', '验证码已过期', 410),
            -2 => throw new BusinessException('VERIFY_CODE_CONSUMED', '验证码已使用', 410),
            default => throw new BusinessException('VERIFY_CODE_INVALID', '验证码不正确', 422),
        };
    }

    /**
     * 生成按请求ID隔离的验证码Redis键。
     */
    private function requestKey(string $requestId): string
    {
        return 'auth:verify:request:' . $requestId;
    }
}

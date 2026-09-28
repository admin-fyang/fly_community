<?php

declare(strict_types=1);

namespace app\Modules\System\Infrastructure\Redis;

use app\model\AppConfigModel;
use app\Modules\System\Domain\Repository\SystemConfigRepository;
use JsonException;
use Predis\Client;
use support\Log;
use Throwable;

/** 使用 Redis 完整快照缓存数据库中已发布的系统配置。 */
final class CachedSystemConfigRepository implements SystemConfigRepository
{
    /** 注册配置键发生不兼容变更，使用新缓存命名空间避免读取迁移前快照。 */
    private const CACHE_KEY = 'chat_fly:system_config:published:v2';
    private const BASE_TTL_SECONDS = 1800;
    private const TTL_JITTER_SECONDS = 300;

    /**
     * 仅当待写版本不低于缓存版本时覆盖快照，防止并发回源把旧配置写回缓存。
     */
    private const WRITE_IF_NEWER_SCRIPT = <<<'LUA'
local current = redis.call('HGET', KEYS[1], 'version')
if current and tonumber(current) > tonumber(ARGV[1]) then
    return 0
end
redis.call('HSET', KEYS[1], 'version', ARGV[1], 'payload', ARGV[2])
redis.call('EXPIRE', KEYS[1], ARGV[3])
return 1
LUA;

    /** 注入当前 Worker 复用的 Redis 客户端。 */
    public function __construct(private readonly Client $redis)
    {
    }

    /** @return array<string, mixed> */
    public function allEnabled(): array
    {
        try {
            $cached = $this->redis->hmget(self::CACHE_KEY, ['payload']);
            if (isset($cached[0]) && is_string($cached[0]) && $cached[0] !== '') {
                return $this->decodeSnapshot($cached[0]);
            }
        } catch (Throwable $exception) {
            $this->logFailure('read', $exception);
        }

        $snapshot = $this->loadFromDatabase();
        $this->writeSnapshot($snapshot);
        return $snapshot;
    }

    /** 失效旧缓存并从数据库重建公开配置快照。 */
    public function refresh(): void
    {
        try {
            $this->redis->del([self::CACHE_KEY]);
        } catch (Throwable $exception) {
            $this->logFailure('invalidate', $exception);
        }

        $this->writeSnapshot($this->loadFromDatabase());
    }

    /** @return array<string, mixed> */
    private function loadFromDatabase(): array
    {
        $snapshot = [];
        $rows = AppConfigModel::query()
            ->where('status', 1)
            ->get(['key', 'value', 'value_format']);

        foreach ($rows as $row) {
            $key = trim((string)$row->key);
            if ($key === '') {
                continue;
            }
            $snapshot[$key] = $this->decodeValue((string)($row->value ?? ''), (string)$row->value_format);
        }

        return $snapshot;
    }

    /** 按声明格式解析整数、开关和 JSON 配置值。 */
    private function decodeValue(string $value, string $format): mixed
    {
        return match ($format) {
            'int', 'switch' => (int)$value,
            'json' => json_decode($value, true, 512, JSON_THROW_ON_ERROR),
            default => $value,
        };
    }

    /** @param array<string, mixed> $snapshot */
    private function writeSnapshot(array $snapshot): void
    {
        try {
            $payload = json_encode($snapshot, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $version = max(0, (int)($snapshot['config_version'] ?? 0));
            $ttl = self::BASE_TTL_SECONDS + random_int(0, self::TTL_JITTER_SECONDS);
            $this->redis->eval(self::WRITE_IF_NEWER_SCRIPT, 1, self::CACHE_KEY, (string)$version, $payload, (string)$ttl);
        } catch (Throwable $exception) {
            $this->logFailure('write', $exception);
        }
    }

    /** @return array<string, mixed> */
    private function decodeSnapshot(string $payload): array
    {
        try {
            $snapshot = json_decode($payload, true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException $exception) {
            try {
                $this->redis->del([self::CACHE_KEY]);
            } catch (Throwable $redisException) {
                $this->logFailure('discard_invalid', $redisException);
            }
            throw $exception;
        }

        if (!is_array($snapshot)) {
            throw new JsonException('系统配置缓存快照必须为对象');
        }
        return $snapshot;
    }

    /** Redis 失败只触发数据库降级，不记录连接参数、配置值或密钥。 */
    private function logFailure(string $operation, Throwable $exception): void
    {
        Log::warning('system_config.cache_failed', [
            'operation' => $operation,
            'exception_class' => $exception::class,
        ]);
    }
}

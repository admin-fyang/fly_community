<?php

declare(strict_types=1);

namespace app\Modules\Account\Application;

use app\enum\UserStatus;
use app\model\AppRealtimeConnectionModel;
use app\model\AppUserModel;
use app\model\AppUserSessionModel;
use app\Modules\User\Domain\Service\PresenceShard;
use app\Support\Transaction\TransactionManager;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Throwable;

/** 实时准入和续期从共享数据库读取撤销事实，签名有效不能代替会话有效。 */
final class RealtimeSessionService
{
    /** 注入凭证验证密钥、事务、连接租期和 Presence 分片配置。 */
    public function __construct(private readonly TransactionManager $transactions, private readonly string $secret,
        private readonly int $checkSeconds, private readonly int $shards)
    {
    }

    /** 校验客户端通过 data.token 提交的凭证，频道完全由服务端生成。 */
    public function connect(array $input): array
    {
        $client = $input['client'] ?? null;
        $data = is_array($input['data'] ?? null) ? $input['data'] : [];
        $token = $data['token'] ?? null;
        if (!$this->validClient($client) || !is_string($token) || strlen($token) > 65536 || strlen($this->secret) < 32) {
            return $this->invalidToken();
        }
        try {
            $claims = JWT::decode($token, new Key($this->secret, 'HS256'));
        } catch (Throwable) {
            return $this->invalidToken();
        }
        if (!is_int($claims->exp ?? null) || $claims->exp <= time()) {
            return $this->invalidToken();
        }
        // Listener 凭证必须有独立用途声明；普通用户即使自报相同名称也不能订阅全部分片。
        if (($claims->sub ?? null) === '__presence_listener__' && ($claims->purpose ?? null) === 'presence_listener') {
            $subs = [];
            for ($shard = 0; $shard < $this->shards; ++$shard) {
                $subs[sprintf('presence:%04d', $shard)] = ['override' => ['force_push_join_leave' => ['value' => true]]];
            }
            return ['result' => ['user' => '__presence_listener__', 'expire_at' => $claims->exp, 'subs' => $subs,
                'meta' => ['kind' => 'presence_listener', 'expires_at' => $claims->exp]]];
        }
        $userId = filter_var($claims->sub ?? null, FILTER_VALIDATE_INT);
        $sessionId = $claims->info->session_id ?? null;
        $deviceId = $claims->info->device_id ?? null;
        if ($userId === false || $userId <= 0 || !is_string($sessionId) || !is_string($deviceId)) {
            return $this->invalidToken();
        }
        return $this->transactions->run(function () use ($client, $userId, $sessionId, $deviceId): array {
            $session = AppUserSessionModel::query()->whereKey($sessionId)->where('user_id', $userId)
                ->where('device_id', $deviceId)->lockForUpdate()->first();
            if (!$this->active($session, $userId)) {
                return $this->revoked();
            }
            $now = time();
            $expiresAt = min($session->expires_at, $now + $this->checkSeconds);
            // 登记与校验持有同一会话锁；撤销事务提交后不存在遗漏的后续有效登记。
            $connection = AppRealtimeConnectionModel::query()->firstOrCreate(['client_id' => $client], ['session_id' => $sessionId,
                'user_id' => $userId, 'created_at' => $now, 'expires_at' => $expiresAt]);
            if ($connection->session_id !== $sessionId || $connection->user_id !== $userId) {
                return $this->invalidToken();
            }
            $this->touch($session, $now);
            return ['result' => ['user' => (string)$userId, 'expire_at' => $expiresAt,
                'info' => ['user_id' => (string)$userId, 'device_id' => $deviceId, 'session_id' => $sessionId],
                'subs' => ['private-user:' . $userId => (object)[], PresenceShard::channel($userId, $this->shards) => (object)[]]]];
        });
    }

    /** Centrifugo 服务端续期，不接受客户端指定新的用户或会话。 */
    public function refresh(array $input): array
    {
        if (!$this->validClient($input['client'] ?? null)) {
            return $this->invalidToken();
        }
        if (($input['user'] ?? null) === '__presence_listener__') {
            $expiresAt = $input['meta']['expires_at'] ?? 0;
            return is_int($expiresAt) && $expiresAt > time() && ($input['meta']['kind'] ?? null) === 'presence_listener'
                ? ['result' => ['expire_at' => $expiresAt]] : $this->invalidToken();
        }
        $connection = AppRealtimeConnectionModel::query()->whereKey($input['client'])->first();
        if ($connection === null || (string)$connection->user_id !== ($input['user'] ?? null)) {
            return $this->revoked();
        }
        return $this->transactions->run(function () use ($connection): array {
            $session = AppUserSessionModel::query()->whereKey($connection->session_id)->where('user_id', $connection->user_id)
                ->lockForUpdate()->first();
            if (!$this->active($session, $connection->user_id)) {
                return $this->revoked();
            }
            $now = time();
            $expiresAt = min($session->expires_at, $now + $this->checkSeconds);
            AppRealtimeConnectionModel::query()->whereKey($connection->client_id)->update(['expires_at' => $expiresAt]);
            $this->touch($session, $now);
            return ['result' => ['expire_at' => $expiresAt]];
        });
    }

    /** 会话有效且用户正常才允许实时访问；不使用 Worker 内用户缓存。 */
    private function active(?AppUserSessionModel $session, int $userId): bool
    {
        return $session !== null && $session->revoked_at === null && $session->expires_at > time()
            && AppUserModel::query()->whereKey($userId)->where('status', UserStatus::Active->value)->exists();
    }

    /** 同一会话一分钟最多写一次活跃时间，避免后台连接高频写放大。 */
    private function touch(AppUserSessionModel $session, int $now): void
    {
        if ($session->last_active_at <= $now - 60) {
            $session->last_active_at = $now;
            $session->save();
        }
    }

    /** 连接ID由受认证的 Centrifugo 回调提供，严格限制格式后登记。 */
    private function validClient(mixed $client): bool
    {
        return is_string($client) && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iD', $client) === 1;
    }

    /** 固定退出协议，前端同时匹配 code 和 reason。 */
    private function revoked(): array
    {
        return ['disconnect' => ['code' => 4501, 'reason' => 'AUTH_SESSION_REVOKED']];
    }

    /** 无效/过期连接凭证允许客户端重新取得短期凭证，不能误标记为会话撤销。 */
    private function invalidToken(): array
    {
        return ['disconnect' => ['code' => 4001, 'reason' => 'AUTH_TOKEN_INVALID']];
    }
}

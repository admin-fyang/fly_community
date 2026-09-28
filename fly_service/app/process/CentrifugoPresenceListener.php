<?php

declare(strict_types=1);

namespace app\process;

use Firebase\JWT\JWT;
use GuzzleHttp\Client;
use JsonException;
use Predis\Client as RedisClient;
use support\Container;
use support\Log;
use Throwable;
use Workerman\Connection\AsyncTcpConnection;
use Workerman\Timer;
use Workerman\Worker;

/**
 * Centrifugo 社区版用户在线状态监听进程。
 *
 * 单实例订阅全部 presence 分片，实时消费 Join/Leave 并维护 Redis；周期对账以
 * Centrifugo Presence 为最终事实，修复实时事件至多一次投递可能造成的状态漂移。
 */
final class CentrifugoPresenceListener
{
    private const LISTENER_USER = '__presence_listener__';

    private ?RedisClient $redis = null;

    private ?Client $http = null;

    private ?AsyncTcpConnection $connection = null;

    private bool $connected = false;

    private int $lastEventAt = 0;

    private int $lastReconcileAt = 0;

    private int $reconnectDelay = 1;

    private int $refreshTimerId = 0;

    private bool $hasConnectedBefore = false;

    private bool $stopping = false;

    /**
     * 初始化基础设施、连接 Centrifugo，并启动离线防抖、对账与健康心跳定时器。
     */
    public function onWorkerStart(Worker $worker): void
    {
        $this->assertConfigured();
        $this->redis = Container::get(RedisClient::class);
        $this->http = new Client();

        $this->connect();
        Timer::add(1.0, fn (): bool => $this->finalizeOffline());
        Timer::add(
            (float)config('centrifugo.presence_reconcile_seconds'),
            fn (): bool => $this->connected ? $this->reconcile() : false,
        );
        Timer::add(5.0, fn (): bool => $this->writeHealth());
    }

    /**
     * Webman 停止时禁止安排重连，并立即把健康状态改为 degraded。
     */
    public function onWorkerStop(Worker $worker): void
    {
        $this->stopping = true;
        $this->connected = false;
        $this->cancelRefreshTimer();
        $this->writeHealth();
        $this->connection?->close();
    }

    /**
     * 建立 Listener WebSocket；wss 使用 Workerman 的 SSL 传输层并保持证书校验。
     */
    private function connect(): void
    {
        $url = $this->webSocketUrl();
        $secure = str_starts_with($url, 'wss://');
        $workermanUrl = $secure ? 'ws://' . substr($url, 6) : $url;
        $socketContext = $secure ? ['ssl' => ['verify_peer' => true, 'verify_peer_name' => true]] : [];

        $connection = new AsyncTcpConnection($workermanUrl, $socketContext);
        if ($secure) {
            $connection->transport = 'ssl';
        }
        $connection->websocketPingInterval = 20;
        $connection->onWebSocketConnect = fn (AsyncTcpConnection $connection): bool => $this->authenticate($connection);
        $connection->onMessage = fn (AsyncTcpConnection $connection, string $message): bool => $this->handleMessage($connection, $message);
        $connection->onError = function (AsyncTcpConnection $connection, int $code, string $message): void {
            $this->connected = false;
            Log::warning('presence.listener.websocket_error', ['code' => $code]);
        };
        $connection->onClose = function (AsyncTcpConnection $connection): void {
            $this->connected = false;
            $this->cancelRefreshTimer();
            if ($this->stopping) {
                return;
            }
            $delay = $this->reconnectDelay;
            $this->reconnectDelay = min(10, $this->reconnectDelay * 2);
            Log::warning('presence.listener.disconnected', ['retry_after_seconds' => $delay]);
            $connection->reconnect($delay);
        };

        $this->connection = $connection;
        $connection->connect();
    }

    /**
     * 发送 Centrifugo JSON 协议 connect 命令；Token 包含全部分片服务端订阅。
     */
    private function authenticate(AsyncTcpConnection $connection): bool
    {
        return $connection->send(json_encode([
            'id' => 1,
            'connect' => [
                ...((bool)config('device_sessions.realtime_proxy_enabled')
                    ? ['data' => ['token' => $this->listenerToken()]]
                    : ['token' => $this->listenerToken()]),
                'name' => 'chatfly-webman-presence-listener',
            ],
        ], JSON_THROW_ON_ERROR));
    }

    /**
     * 解析一个 WebSocket frame 中可能包含的多条换行分隔 JSON 协议消息。
     */
    private function handleMessage(AsyncTcpConnection $connection, string $message): bool
    {
        if ($message === '' || $message === '{}') {
            return $message === '{}' ? $connection->send('{}') : true;
        }

        foreach (preg_split('/\r?\n/', trim($message)) ?: [] as $rawFrame) {
            if ($rawFrame === '') {
                continue;
            }
            try {
                $frame = json_decode($rawFrame, true, 512, JSON_THROW_ON_ERROR);
            } catch (JsonException) {
                Log::warning('presence.listener.invalid_frame');
                continue;
            }
            if (!is_array($frame)) {
                continue;
            }
            if (isset($frame['error'])) {
                $this->connected = false;
                Log::error('presence.listener.protocol_error', [
                    'code' => (int)($frame['error']['code'] ?? 0),
                ]);
                $connection->close();
                return false;
            }
            if (isset($frame['connect'])) {
                $this->onConnected();
                continue;
            }
            if (isset($frame['push']) && is_array($frame['push'])) {
                $this->handlePush($frame['push']);
            }
        }
        return true;
    }

    /**
     * 连接认证成功后立即对账，并在 Token 到期前主动重连以换取新 Token。
     */
    private function onConnected(): void
    {
        $this->connected = true;
        $this->reconnectDelay = 1;
        if ($this->hasConnectedBefore) {
            $this->incrementMetric('presence_listener_reconnect_total');
        }
        $this->hasConnectedBefore = true;
        Log::info('presence.listener.connected');
        $this->reconcile();

        $this->cancelRefreshTimer();
        $refreshAfter = max(60, (int)config('centrifugo.presence_listener_token_ttl_seconds') - 60);
        $this->refreshTimerId = Timer::add($refreshAfter, function (): void {
            $this->connection?->close();
        }, [], false);
    }

    /**
     * 消费 server-side subscription 的 Join/Leave 推送。
     *
     * @param array<string,mixed> $push Centrifugo Push 消息
     */
    private function handlePush(array $push): void
    {
        $join = isset($push['join']) && is_array($push['join']);
        $leave = isset($push['leave']) && is_array($push['leave']);
        if (!$join && !$leave) {
            return;
        }
        $event = $join ? $push['join'] : $push['leave'];
        $info = isset($event['info']) && is_array($event['info']) ? $event['info'] : $event;
        $userId = (string)($info['user'] ?? '');
        $clientId = (string)($info['client'] ?? '');
        if ($userId === '' || $userId === self::LISTENER_USER || $clientId === '') {
            return;
        }
        $connInfo = $info['conn_info'] ?? [];
        if (is_string($connInfo)) {
            $connInfo = json_decode($connInfo, true) ?: [];
        }
        $deviceId = strtolower((string)(is_array($connInfo) ? ($connInfo['device_id'] ?? '') : ''));
        $join ? $this->applyJoin($userId, $clientId, $deviceId) : $this->applyLeave($userId, $clientId, $deviceId);
    }

    /** 将上线连接写入用户和设备集合，并取消待离线任务。 */
    private function applyJoin(string $userId, string $clientId, string $deviceId): void
    {
        try {
            $this->redis()->transaction(function ($tx) use ($userId, $clientId, $deviceId): void {
                $tx->sadd($this->userClientsKey($userId), [$clientId]);
                $tx->hmset($this->clientMetaKey($clientId), ['user_id' => $userId, 'device_id' => $deviceId]);
                $tx->expire($this->clientMetaKey($clientId), 86400);
                if ($this->validDeviceId($deviceId)) {
                    $tx->sadd($this->deviceClientsKey($userId, $deviceId), [$clientId]);
                }
                $tx->set($this->userStateKey($userId), 'online');
                $tx->zrem($this->pendingOfflineKey(), $userId);
            });
            $this->lastEventAt = time();
            $this->incrementMetric('presence_join_total');
        } catch (Throwable $exception) {
            $this->logRedisFailure('join', $exception);
        }
    }

    /** 移除离线连接；用户最后一个连接离开后进入防抖队列。 */
    private function applyLeave(string $userId, string $clientId, string $deviceId): void
    {
        try {
            if ($deviceId === '') {
                $meta = $this->redis()->hgetall($this->clientMetaKey($clientId));
                $deviceId = strtolower((string)($meta['device_id'] ?? ''));
            }
            $this->redis()->transaction(function ($tx) use ($userId, $clientId, $deviceId): void {
                $tx->srem($this->userClientsKey($userId), $clientId);
                if ($this->validDeviceId($deviceId)) {
                    $tx->srem($this->deviceClientsKey($userId, $deviceId), $clientId);
                }
                $tx->del([$this->clientMetaKey($clientId)]);
            });
            if ((int)$this->redis()->scard($this->userClientsKey($userId)) === 0) {
                $this->redis()->zadd(
                    $this->pendingOfflineKey(),
                    [$userId => time() + (int)config('centrifugo.presence_offline_grace_seconds')],
                );
            }
            $this->lastEventAt = time();
            $this->incrementMetric('presence_leave_total');
        } catch (Throwable $exception) {
            $this->logRedisFailure('leave', $exception);
        }
    }

    /**
     * 完成到期离线任务；再次确认连接数，避免切网重连期间错误离线。
     */
    private function finalizeOffline(): bool
    {
        try {
            $users = $this->redis()->zrangebyscore($this->pendingOfflineKey(), '-inf', (string)time());
            foreach ($users as $userId) {
                if ((int)$this->redis()->scard($this->userClientsKey((string)$userId)) > 0) {
                    $this->redis()->zrem($this->pendingOfflineKey(), (string)$userId);
                    continue;
                }
                $this->redis()->transaction(function ($tx) use ($userId): void {
                    $tx->set($this->userStateKey((string)$userId), 'offline');
                    $tx->set($this->userLastSeenKey((string)$userId), time());
                    $tx->zrem($this->pendingOfflineKey(), (string)$userId);
                });
            }
            return true;
        } catch (Throwable $exception) {
            $this->logRedisFailure('finalize', $exception);
            return false;
        }
    }

    /**
     * 通过一次 Centrifugo Batch API 并行查询全部分片，并原子重建 Redis 在线集合。
     */
    private function reconcile(): bool
    {
        $startedAt = microtime(true);
        try {
            $commands = [];
            $shardCount = (int)config('centrifugo.presence_shard_count');
            for ($shard = 0; $shard < $shardCount; $shard++) {
                $commands[] = ['presence' => ['channel' => sprintf('presence:%04d', $shard)]];
            }
            $response = $this->http()->post(rtrim((string)config('centrifugo.api_url'), '/') . '/api/batch', [
                'headers' => ['X-API-Key' => (string)config('centrifugo.api_key')],
                'json' => ['parallel' => true, 'commands' => $commands],
                'timeout' => (float)config('centrifugo.request_timeout_seconds'),
                'http_errors' => false,
            ]);
            $body = json_decode((string)$response->getBody(), true, 512, JSON_THROW_ON_ERROR);
            $replies = is_array($body) ? ($body['replies'] ?? null) : null;
            if ($response->getStatusCode() !== 200 || !is_array($replies) || count($replies) !== $shardCount) {
                throw new \RuntimeException('presence_batch_invalid');
            }
            $expected = [];
            foreach ($replies as $reply) {
                if (!is_array($reply) || isset($reply['error'])) {
                    throw new \RuntimeException('presence_command_failed');
                }
                foreach (($reply['presence']['presence'] ?? []) as $clientId => $info) {
                    if (!is_array($info)) {
                        continue;
                    }
                    $userId = (string)($info['user'] ?? '');
                    if ($userId === '' || $userId === self::LISTENER_USER) {
                        continue;
                    }
                    $connInfo = $info['conn_info'] ?? [];
                    $deviceId = strtolower((string)(is_array($connInfo) ? ($connInfo['device_id'] ?? '') : ''));
                    $expected[$userId][(string)($info['client'] ?? $clientId)] = $deviceId;
                }
            }
            $expectedConnections = array_sum(array_map('count', $expected));
            $currentConnections = count($this->scanKeys('im:presence:client:*'));
            $mismatch = abs($expectedConnections - $currentConnections);
            $this->replacePresenceState($expected);
            $this->lastReconcileAt = time();
            $this->redis()->set('im:presence:listener:last_reconcile_at', $this->lastReconcileAt);
            $this->redis()->hmset('im:presence:listener:metrics', [
                'presence_online_users' => count($expected),
                'presence_online_connections' => $expectedConnections,
                'presence_reconcile_duration_ms' => (int)round((microtime(true) - $startedAt) * 1000),
            ]);
            $this->incrementMetric('presence_reconcile_total');
            if ($mismatch > 0) {
                $this->redis()->hincrby('im:presence:listener:metrics', 'presence_reconcile_mismatch_total', $mismatch);
            }
            Log::info('presence.listener.reconciled', ['online_users' => count($expected)]);
            return true;
        } catch (Throwable $exception) {
            // 对账异常可能发生在MULTI事务中。主动断开可清除连接上的事务状态，
            // 下一次健康心跳或事件写入会由Predis自动建立干净连接。
            $this->resetRedisConnection();
            Log::error('presence.listener.reconcile_failed', [
                'exception_class' => $exception::class,
                'error_fingerprint' => substr(hash('sha256', $exception::class), 0, 16),
            ]);
            return false;
        }
    }

    /**
     * @param array<string,array<string,string>> $expected 用户、客户端及设备快照
     */
    private function replacePresenceState(array $expected): void
    {
        $connectionKeys = $this->scanKeys('im:presence:user:*:clients');
        $metaKeys = $this->scanKeys('im:presence:client:*');
        $previousUsers = [];
        foreach ($connectionKeys as $key) {
            if (preg_match('/^im:presence:user:([^:]+):clients$/', $key, $matches) === 1) {
                $previousUsers[$matches[1]] = true;
            }
        }
        $this->redis()->transaction(function ($tx) use ($connectionKeys, $metaKeys, $previousUsers, $expected): void {
            foreach (array_merge($connectionKeys, $metaKeys) as $key) {
                $tx->del([$key]);
            }
            foreach ($expected as $userId => $clients) {
                // PHP会把纯数字字符串数组键自动转换为int；这里必须恢复为字符串，
                // 否则strict_types下传入userClientsKey(string)会在首次出现在线用户时抛TypeError。
                $userId = (string)$userId;
                foreach ($clients as $clientId => $deviceId) {
                    $tx->sadd($this->userClientsKey($userId), [$clientId]);
                    $tx->hmset($this->clientMetaKey($clientId), ['user_id' => $userId, 'device_id' => $deviceId]);
                    $tx->expire($this->clientMetaKey($clientId), 86400);
                    if ($this->validDeviceId($deviceId)) {
                        $tx->sadd($this->deviceClientsKey($userId, $deviceId), [$clientId]);
                    }
                }
                $tx->set($this->userStateKey($userId), 'online');
                $tx->zrem($this->pendingOfflineKey(), $userId);
                unset($previousUsers[$userId]);
            }
            foreach (array_keys($previousUsers) as $userId) {
                $tx->zadd($this->pendingOfflineKey(), [$userId => time() + (int)config('centrifugo.presence_offline_grace_seconds')]);
            }
        });
    }

    /** @return list<string> */
    private function scanKeys(string $pattern): array
    {
        $cursor = '0';
        $keys = [];
        do {
            $result = $this->redis()->scan($cursor, ['match' => $pattern, 'count' => 500]);
            $cursor = (string)($result[0] ?? '0');
            foreach (($result[1] ?? []) as $key) {
                $keys[] = (string)$key;
            }
        } while ($cursor !== '0');
        return $keys;
    }

    /** 写入业务进程据以判定 Presence 可用性的健康事实。 */
    private function writeHealth(): bool
    {
        try {
            $state = $this->connected && $this->lastReconcileAt > 0 ? 'healthy' : 'degraded';
            $this->redis()->set('im:presence:listener:status', json_encode([
                'state' => $state,
                'last_event_at' => $this->lastEventAt,
                'last_reconcile_at' => $this->lastReconcileAt,
                'updated_at' => time(),
            ], JSON_THROW_ON_ERROR));
            $this->redis()->hset(
                'im:presence:listener:metrics',
                'presence_listener_connected',
                $state === 'healthy' ? 1 : 0,
            );
            return true;
        } catch (Throwable $exception) {
            $this->logRedisFailure('health', $exception);
            return false;
        }
    }

    /** 生成 Listener 服务身份 Token，并为每个分片强制接收 Join/Leave。 */
    private function listenerToken(): string
    {
        $subs = [];
        for ($shard = 0; $shard < (int)config('centrifugo.presence_shard_count'); $shard++) {
            $subs[sprintf('presence:%04d', $shard)] = [
                'override' => ['force_push_join_leave' => ['value' => true]],
            ];
        }
        $now = time();
        return JWT::encode([
            'sub' => self::LISTENER_USER,
            'purpose' => 'presence_listener',
            'iat' => $now,
            'exp' => $now + (int)config('centrifugo.presence_listener_token_ttl_seconds'),
            'subs' => $subs,
        ], (string)config('centrifugo.token_hmac_secret'), 'HS256');
    }

    /** 确认进程启动所需配置完整，防止无效进程伪装为健康。 */
    private function assertConfigured(): void
    {
        if (!(bool)config('centrifugo.enabled')
            || strlen((string)config('centrifugo.token_hmac_secret')) < 32
            || (string)config('centrifugo.api_key') === '') {
            throw new \RuntimeException('Centrifugo Presence Listener 配置不完整');
        }
    }

    /** 返回启用原生 WebSocket ping/pong 的 Listener 地址。 */
    private function webSocketUrl(): string
    {
        $url = (string)config('centrifugo.presence_listener_ws_url');
        return str_contains($url, '?') ? $url . '&cf_ws_frame_ping_pong=true' : $url . '?cf_ws_frame_ping_pong=true';
    }

    /** 删除主动换 Token 定时器，避免重连后旧定时器误关新连接。 */
    private function cancelRefreshTimer(): void
    {
        if ($this->refreshTimerId > 0) {
            Timer::del($this->refreshTimerId);
            $this->refreshTimerId = 0;
        }
    }

    /** 记录不含 Redis 地址、密码、键值和业务数据的失败摘要。 */
    private function logRedisFailure(string $operation, Throwable $exception): void
    {
        // 不能继续复用可能停留在MULTI或错误协议状态的连接，否则一次失败会让健康心跳永久陈旧。
        $this->resetRedisConnection();
        $this->incrementMetric('presence_event_error_total');
        Log::error('presence.listener.redis_failed', [
            'operation' => $operation,
            'exception_class' => $exception::class,
        ]);
    }

    /**
     * 丢弃当前Redis网络连接；Predis会在下一条命令时使用原配置自动重连。
     */
    private function resetRedisConnection(): void
    {
        try {
            $this->redis?->disconnect();
        } catch (Throwable) {
            // 连接已经失效时disconnect也可能失败；这里只尽力清理，原始异常由调用方记录。
        }
    }

    /** 累加不携带用户维度的 Listener 运行指标；指标失败不得中断状态主流程。 */
    private function incrementMetric(string $metric): void
    {
        try {
            $this->redis()->hincrby('im:presence:listener:metrics', $metric, 1);
        } catch (Throwable) {
            // Redis 主流程已经有独立错误日志，指标写入失败不重复制造日志风暴。
        }
    }

    /** 返回当前 Listener 独占复用的 Redis 客户端。 */
    private function redis(): RedisClient
    {
        return $this->redis ?? throw new \RuntimeException('Presence Redis 尚未初始化');
    }

    /** 返回仅用于 Presence 周期对账的 HTTP 客户端。 */
    private function http(): Client
    {
        return $this->http ?? throw new \RuntimeException('Presence HTTP 客户端尚未初始化');
    }

    /** 判断连接信息中的安装实例ID是否为规范 UUID v4。 */
    private function validDeviceId(string $deviceId): bool
    {
        return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $deviceId) === 1;
    }

    /** 返回用户全部连接集合键。 */
    private function userClientsKey(string $userId): string { return 'im:presence:user:' . $userId . ':clients'; }

    /** 返回用户指定安装实例连接集合键。 */
    private function deviceClientsKey(string $userId, string $deviceId): string { return 'im:presence:user:' . $userId . ':device:' . $deviceId . ':clients'; }

    /** 返回用户当前在线状态键。 */
    private function userStateKey(string $userId): string { return 'im:presence:user:' . $userId . ':state'; }

    /** 返回用户最后离线时间键。 */
    private function userLastSeenKey(string $userId): string { return 'im:presence:user:' . $userId . ':last_seen'; }

    /** 返回 Centrifugo 客户端连接元数据键。 */
    private function clientMetaKey(string $clientId): string { return 'im:presence:client:' . $clientId; }

    /** 返回等待离线防抖确认的用户有序集合键。 */
    private function pendingOfflineKey(): string { return 'im:presence:offline_pending'; }
}

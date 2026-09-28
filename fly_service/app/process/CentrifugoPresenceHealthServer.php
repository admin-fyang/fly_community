<?php

declare(strict_types=1);

namespace app\process;

use Predis\Client;
use support\Container;
use Throwable;
use Workerman\Connection\TcpConnection;
use Workerman\Protocols\Http\Request;
use Workerman\Protocols\Http\Response;

/**
 * Presence Listener 内网健康检查进程。
 *
 * 只读取 Redis 健康事实，不暴露在线用户、设备、连接ID或基础设施凭据。
 */
final class CentrifugoPresenceHealthServer
{
    /**
     * 处理 GET /health；Listener 未连接或心跳陈旧时返回 503。
     */
    public function onMessage(TcpConnection $connection, Request $request): void
    {
        if ($request->method() !== 'GET' || $request->path() !== '/health') {
            $connection->send(new Response(404, ['Content-Type' => 'text/plain'], "not found\n"));
            return;
        }

        $statusCode = 503;
        $body = ['status' => 'degraded'];
        try {
            /** @var Client $redis */
            $redis = Container::get(Client::class);
            $raw = $redis->get('im:presence:listener:status');
            $status = is_string($raw) ? json_decode($raw, true) : null;
            $fresh = is_array($status)
                && ($status['state'] ?? null) === 'healthy'
                && (int)($status['updated_at'] ?? 0) >= time() - (int)config('centrifugo.presence_listener_stale_seconds');
            if ($fresh) {
                $statusCode = 200;
                $body = [
                    'status' => 'healthy',
                    'centrifugo' => 'connected',
                    'redis' => 'connected',
                    'last_event_at' => (int)($status['last_event_at'] ?? 0),
                    'last_reconcile_at' => (int)($status['last_reconcile_at'] ?? 0),
                ];
            }
        } catch (Throwable) {
            $body = ['status' => 'degraded', 'redis' => 'disconnected'];
        }

        $connection->send(new Response(
            $statusCode,
            ['Content-Type' => 'application/json; charset=utf-8'],
            json_encode($body, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        ));
    }
}

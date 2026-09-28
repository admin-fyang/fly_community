<?php

declare(strict_types=1);

$apiUrl = rtrim((string)(getenv('CENTRIFUGO_API_URL') ?: 'http://127.0.0.1:8000'), '/');
if (str_ends_with($apiUrl, '/api')) {
    $apiUrl = substr($apiUrl, 0, -4);
}
$listenerWsUrl = (string)(getenv('PRESENCE_LISTENER_WS_URL') ?: '');
if ($listenerWsUrl === '') {
    // 默认从内网Server API地址推导WebSocket地址，避免Listener绕公网反向代理。
    $listenerWsUrl = (string)preg_replace('/^http/', 'ws', $apiUrl) . '/connection/websocket';
}

return [
    'enabled' => filter_var(getenv('CENTRIFUGO_ENABLED') ?: 'false', FILTER_VALIDATE_BOOL),
    'api_url' => $apiUrl,
    'public_ws_url' => (string)(getenv('CENTRIFUGO_PUBLIC_WS_URL') ?: 'ws://127.0.0.1:8000/connection/websocket'),
    'api_key' => (string)(getenv('CENTRIFUGO_API_KEY') ?: ''),
    'token_hmac_secret' => (string)(getenv('CENTRIFUGO_TOKEN_HMAC_SECRET') ?: ''),
    'token_ttl_seconds' => max(60, (int)(getenv('CENTRIFUGO_TOKEN_TTL_SECONDS') ?: 300)),
    'request_timeout_seconds' => max(1.0, (float)(getenv('CENTRIFUGO_REQUEST_TIMEOUT_SECONDS') ?: 3)),
    'outbox_interval_seconds' => max(0.1, (float)(getenv('CENTRIFUGO_OUTBOX_INTERVAL_SECONDS') ?: 0.5)),
    'outbox_batch_size' => max(1, min(500, (int)(getenv('CENTRIFUGO_OUTBOX_BATCH_SIZE') ?: 100))),
    'outbox_max_retries' => max(1, (int)(getenv('CENTRIFUGO_OUTBOX_MAX_RETRIES') ?: 8)),
    'outbox_retry_base_seconds' => max(1, (int)(getenv('CENTRIFUGO_OUTBOX_RETRY_BASE_SECONDS') ?: 2)),
    'outbox_retry_max_seconds' => max(1, (int)(getenv('CENTRIFUGO_OUTBOX_RETRY_MAX_SECONDS') ?: 300)),
    'outbox_lock_seconds' => max(5, (int)(getenv('CENTRIFUGO_OUTBOX_LOCK_SECONDS') ?: 15)),
    'outbox_worker_count' => max(1, (int)(getenv('CENTRIFUGO_OUTBOX_WORKER_COUNT') ?: 1)),
    // 分片数属于线上协议，变更时必须同步迁移Listener和所有客户端连接Token。
    'presence_shard_count' => max(1, (int)(getenv('PRESENCE_SHARD_COUNT') ?: 256)),
    // Listener每5秒写健康心跳；20秒未更新即允许FCM兜底，避免把陈旧在线状态当成事实。
    'presence_listener_stale_seconds' => max(10, (int)(getenv('PRESENCE_LISTENER_STALE_SECONDS') ?: 20)),
    // Listener优先连接内网地址；未单独配置时复用客户端WebSocket地址。
    'presence_listener_ws_url' => $listenerWsUrl,
    'presence_offline_grace_seconds' => max(1, (int)(getenv('PRESENCE_OFFLINE_GRACE_SECONDS') ?: 5)),
    'presence_reconcile_seconds' => max(10, (int)(getenv('PRESENCE_RECONCILE_SECONDS') ?: 60)),
    'presence_listener_token_ttl_seconds' => max(300, (int)(getenv('PRESENCE_LISTENER_TOKEN_TTL_SECONDS') ?: 3600)),
    // 仅监听回环地址，供本机进程管理器和监控探针访问。
    'presence_health_listen' => (string)(getenv('PRESENCE_HEALTH_LISTEN') ?: 'http://127.0.0.1:9092'),
];

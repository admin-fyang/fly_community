<?php

declare(strict_types=1);

/** 设备会话管理参数；快照过期后由客户端刷新首页恢复。 */
return [
    'snapshot_ttl_seconds' => 600,
    'snapshot_max_sessions' => 10000,
    'requests_per_minute' => 60,
    // 部署 connect/refresh proxy 后开启；旧 JWT 直连入口必须同时关闭。
    'realtime_proxy_enabled' => filter_var(getenv('AUTH_REALTIME_PROXY_ENABLED') ?: 'false', FILTER_VALIDATE_BOOL),
    'proxy_secret' => (string)(getenv('AUTH_REALTIME_PROXY_SECRET') ?: ''),
    'connection_check_seconds' => 30,
];

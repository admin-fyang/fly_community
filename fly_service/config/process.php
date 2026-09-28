<?php

declare(strict_types=1);

use app\process\CentrifugoOutboxWorker;
use app\process\CentrifugoPresenceHealthServer;
use app\process\CentrifugoPresenceListener;
use app\process\FileMultipartCleanupWorker;
use app\process\Http;
use app\process\SessionControlWorker;
use support\Log;
use support\Request;

/** 社区版只启动基础 API、单聊实时投递与文件清理进程。 */
return array_filter([
    'webman' => [
        'handler' => Http::class,
        'listen' => 'http://0.0.0.0:8787',
        'count' => cpu_count() * 4,
        'user' => '',
        'group' => '',
        'reusePort' => false,
        'eventLoop' => '',
        'context' => [],
        'constructor' => [
            'requestClass' => Request::class,
            'logger' => Log::channel('default'),
            'appPath' => app_path(),
            'publicPath' => public_path(),
        ],
    ],
    'session-control' => [
        'handler' => SessionControlWorker::class,
        'count' => 1,
        'enable' => (bool) config('device_sessions.realtime_proxy_enabled'),
    ],
    'centrifugo-outbox' => [
        'handler' => CentrifugoOutboxWorker::class,
        'count' => (int) config('centrifugo.outbox_worker_count'),
        'reloadable' => true,
        'enable' => (bool) config('centrifugo.enabled') && (string) config('centrifugo.api_key') !== '',
    ],
    'centrifugo-presence-listener' => [
        'handler' => CentrifugoPresenceListener::class,
        'count' => 1,
        'reloadable' => false,
        'enable' => (bool) config('centrifugo.enabled')
            && strlen((string) config('centrifugo.token_hmac_secret')) >= 32
            && (string) config('centrifugo.api_key') !== '',
    ],
    'centrifugo-presence-health' => [
        'handler' => CentrifugoPresenceHealthServer::class,
        'listen' => (string) config('centrifugo.presence_health_listen'),
        'count' => 1,
        'reloadable' => false,
        'enable' => (bool) config('centrifugo.enabled'),
    ],
    'file-multipart-cleanup' => [
        'handler' => FileMultipartCleanupWorker::class,
        'count' => 1,
        'reloadable' => true,
        'enable' => (string) config('rustfs.endpoint') !== ''
            && (string) config('rustfs.access_key') !== ''
            && (string) config('rustfs.secret_key') !== '',
    ],
], static fn(array $process): bool => $process['enable'] ?? true);

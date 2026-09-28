<?php

declare(strict_types=1);

return [
    // 允许来源只在此处维护；生产部署时替换为实际 Web 前端完整来源。
    'allowed_origins' => [
        'https://flychat.cc',
        'https://www.flychat.cc',
        'http://localhost:8000',
        'http://localhost:8888',
        'http://localhost:55746'
    ],
    'allowed_methods' => 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'allowed_headers' => 'Authorization, Content-Type, X-Request-ID, X-Client-Platform',
    'exposed_headers' => 'X-Request-ID',
    'allow_credentials' => true,
    'max_age' => 600,
];

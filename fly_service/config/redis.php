<?php

declare(strict_types=1);

return [
    'scheme' => 'tcp',
    'host' => getenv('REDIS_HOST') ?: '127.0.0.1',
    'port' => (int) (getenv('REDIS_PORT') ?: 6379),
    'password' => getenv('REDIS_PASSWORD') ?: null,
    'database' => (int) (getenv('REDIS_DATABASE') ?: 0),
    'timeout' => 2.0,
    'read_write_timeout' => 2.0,
];

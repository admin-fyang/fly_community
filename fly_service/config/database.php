<?php

declare(strict_types=1);

return [
    'driver' => 'mysql',
    'host' => getenv('DB_HOST') ?: '127.0.0.1',
    'port' => (int) (getenv('DB_PORT') ?: 3306),
    'database' => getenv('DB_DATABASE') ?: 'chat_fly',
    'username' => getenv('DB_USERNAME') ?: 'chat_fly',
    'password' => getenv('DB_PASSWORD') ?: '',
    'unix_socket' => getenv('DB_SOCKET') ?: '',
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_unicode_ci',
    'prefix' => '',
    'strict' => true,
    'engine' => 'InnoDB',
    'options' => [
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::ATTR_STRINGIFY_FETCHES => false,
    ],
];

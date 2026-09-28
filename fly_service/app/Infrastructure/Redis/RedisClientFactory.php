<?php

declare(strict_types=1);

namespace app\Infrastructure\Redis;

use Predis\Client;

/**
 * 创建每个 Worker 复用的 Predis 客户端。
 */
final class RedisClientFactory
{
    /**
     * @param array<string, mixed> $config
     */
    public function create(array $config): Client
    {
        $parameters = [
            'scheme' => $config['scheme'],
            'host' => $config['host'],
            'port' => $config['port'],
            'database' => $config['database'],
            'timeout' => $config['timeout'],
            'read_write_timeout' => $config['read_write_timeout'],
        ];
        if (!empty($config['password'])) {
            $parameters['password'] = $config['password'];
        }

        return new Client($parameters);
    }
}

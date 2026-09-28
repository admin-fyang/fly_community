<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Provider;

use app\Modules\Account\Domain\Repository\RealtimeDisconnector;
use GuzzleHttp\ClientInterface;
use RuntimeException;
use Throwable;

/** 调用 Centrifugo Server API；日志仅记录安全错误，不暴露 API 密钥。 */
final class HttpRealtimeDisconnector implements RealtimeDisconnector
{
    /** 注入 HTTP 适配器和内部控制接口地址。 */
    public function __construct(private readonly ClientInterface $http, private readonly string $url, private readonly string $key)
    {
    }

    /** 必须同时提供用户和连接ID，确保 Android 主后台连接逐条撤销。 */
    public function disconnect(int $userId, string $clientId): void
    {
        if ($userId <= 0 || $clientId === '' || $this->url === '' || $this->key === '') {
            throw new RuntimeException('realtime_disconnect_invalid');
        }
        try {
            $response = $this->http->request('POST', rtrim($this->url, '/') . '/api/disconnect', [
                'headers' => ['X-API-Key' => $this->key],
                'json' => ['user' => (string)$userId, 'client' => $clientId,
                    'disconnect' => ['code' => 4501, 'reason' => 'AUTH_SESSION_REVOKED']],
                'http_errors' => false, 'timeout' => 3, 'connect_timeout' => 1,
            ]);
            $body = json_decode((string)$response->getBody(), true, 512, JSON_THROW_ON_ERROR);
            if ($response->getStatusCode() !== 200 || !is_array($body) || isset($body['error']) || !isset($body['result']) || !is_array($body['result'])) {
                throw new RuntimeException('realtime_disconnect_rejected');
            }
        } catch (Throwable) {
            throw new RuntimeException('realtime_disconnect_failed');
        }
    }
}

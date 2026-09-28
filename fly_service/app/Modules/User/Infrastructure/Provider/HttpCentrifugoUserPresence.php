<?php

declare(strict_types=1);

namespace app\Modules\User\Infrastructure\Provider;

use app\Modules\User\Domain\Exception\UserPresenceUnavailableException;
use app\Modules\User\Domain\Service\UserPresence;
use GuzzleHttp\ClientInterface;
use GuzzleHttp\Exception\GuzzleException;
use JsonException;

/**
 * 通过 Centrifugo HTTP API 查询用户私有频道在线状态。
 */
final class HttpCentrifugoUserPresence implements UserPresence
{
    /**
     * 通过Presence明细判断指定设备是否在线，保留为Redis Listener切换失败时的诊断实现。
     */
    public function isDeviceOnline(int $userId, string $deviceId): bool
    {
        $this->assertConfigured();
        try {
            $response = $this->client->post($this->apiUrl . '/api/presence', [
                'headers' => ['X-API-Key' => $this->apiKey, 'Content-Type' => 'application/json'],
                'json' => ['channel' => 'private-user:' . $userId],
                'timeout' => $this->timeoutSeconds,
                'http_errors' => false,
            ]);
        } catch (\Throwable) {
            throw new UserPresenceUnavailableException('centrifugo_transport_error');
        }
        $data = json_decode((string)$response->getBody(), true);
        if ($response->getStatusCode() !== 200 || !is_array($data) || isset($data['error'])) {
            throw new UserPresenceUnavailableException('centrifugo_invalid_response');
        }
        foreach (($data['result']['presence'] ?? []) as $client) {
            if (is_array($client) && ($client['conn_info']['device_id'] ?? null) === $deviceId) {
                return true;
            }
        }
        return false;
    }

    /**
     * 注入 Centrifugo 服务端连接配置。
     */
    public function __construct(
        private readonly ClientInterface $client,
        private readonly bool $enabled,
        private readonly string $apiUrl,
        private readonly string $apiKey,
        private readonly float $timeoutSeconds,
    ) {
    }

    /**
     * 判断指定用户是否至少有一个实时连接。
     */
    public function isOnline(int $userId): bool
    {
        return $this->onlineStates([$userId])[$userId];
    }

    /**
     * 使用 Centrifugo batch + presence_stats 一次查询多个用户。
     *
     * 批量响应中任一命令失败都会让整次查询失败，防止把协议错误或
     * 未开启 presence 错误地解释为用户离线。
     *
     * @param list<int> $userIds 用户ID列表
     * @return array<int,bool> 以用户ID为键的在线状态
     */
    public function onlineStates(array $userIds): array
    {
        $userIds = array_values(array_unique(array_filter(
            array_map(static fn (mixed $userId): int => (int)$userId, $userIds),
            static fn (int $userId): bool => $userId > 0,
        )));
        if ($userIds === []) {
            return [];
        }
        $this->assertConfigured();

        try {
            $response = $this->client->request('POST', $this->apiUrl . '/api/batch', [
                'headers' => [
                    'Accept' => 'application/json',
                    'Content-Type' => 'application/json',
                    'X-API-Key' => $this->apiKey,
                ],
                'json' => [
                    'parallel' => true,
                    'commands' => array_map(
                        static fn (int $userId): array => [
                            'presence_stats' => ['channel' => 'private-user:' . $userId],
                        ],
                        $userIds,
                    ),
                ],
                'http_errors' => false,
                'connect_timeout' => $this->timeoutSeconds,
                'timeout' => $this->timeoutSeconds,
            ]);
        } catch (GuzzleException) {
            throw new UserPresenceUnavailableException('centrifugo_transport_error');
        }

        $status = $response->getStatusCode();
        if ($status < 200 || $status >= 300) {
            throw new UserPresenceUnavailableException('centrifugo_http_' . $status);
        }

        try {
            $body = json_decode((string)$response->getBody(), true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            throw new UserPresenceUnavailableException('centrifugo_invalid_response');
        }
        $replies = is_array($body) ? ($body['replies'] ?? null) : null;
        if (!is_array($replies) || count($replies) !== count($userIds)) {
            throw new UserPresenceUnavailableException('centrifugo_invalid_response');
        }

        $states = [];
        foreach ($userIds as $index => $userId) {
            $reply = $replies[$index] ?? null;
            if (!is_array($reply) || isset($reply['error'])) {
                throw new UserPresenceUnavailableException('centrifugo_presence_error');
            }
            $stats = $reply['presence_stats'] ?? null;
            if (!is_array($stats) || !array_key_exists('num_clients', $stats)) {
                throw new UserPresenceUnavailableException('centrifugo_invalid_response');
            }
            $states[$userId] = (int)$stats['num_clients'] > 0;
        }

        return $states;
    }

    /**
     * 确认在线状态查询所需配置完整。
     */
    private function assertConfigured(): void
    {
        if (!$this->enabled || $this->apiUrl === '' || $this->apiKey === '') {
            throw new UserPresenceUnavailableException('centrifugo_config_invalid');
        }
    }
}

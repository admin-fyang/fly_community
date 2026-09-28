<?php

declare(strict_types=1);

namespace app\Modules\Im\Infrastructure\Provider;

use app\Modules\Im\Domain\Exception\CentrifugoPublishException;
use app\Modules\Im\Domain\Service\CentrifugoPublisher;
use GuzzleHttp\ClientInterface;
use GuzzleHttp\Exception\GuzzleException;
use JsonException;

/**
 * 通过Centrifugo HTTP API发布用户事件。
 */
final class HttpCentrifugoPublisher implements CentrifugoPublisher
{
    /**
     * 注入HTTP客户端和Centrifugo服务端配置。
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
     * 将事件发布到Centrifugo用户频道。
     *
     * Centrifugo业务错误可能使用HTTP 200返回，因此必须同时检查响应体中的error字段。
     *
     * @param string $channel Centrifugo频道
     * @param array<string,mixed> $payload 统一事件载荷
     */
    public function publish(string $channel, array $payload): void
    {
        if (!$this->enabled || $this->apiKey === '' || $this->apiUrl === '') {
            throw new CentrifugoPublishException('centrifugo_config_invalid', false);
        }

        try {
            $response = $this->client->request('POST', $this->apiUrl . '/api/publish', [
                'headers' => [
                    'Accept' => 'application/json',
                    'Content-Type' => 'application/json',
                    'X-API-Key' => $this->apiKey,
                ],
                'json' => [
                    'channel' => $channel,
                    'data' => $payload,
                ],
                'http_errors' => false,
                'connect_timeout' => $this->timeoutSeconds,
                'timeout' => $this->timeoutSeconds,
            ]);
        } catch (GuzzleException) {
            throw new CentrifugoPublishException('centrifugo_transport_error', true);
        }

        $status = $response->getStatusCode();
        if ($status === 429 || $status >= 500) {
            throw new CentrifugoPublishException('centrifugo_http_' . $status, true);
        }
        if ($status < 200 || $status >= 300) {
            throw new CentrifugoPublishException('centrifugo_http_' . $status, false);
        }

        try {
            $body = json_decode((string)$response->getBody(), true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            throw new CentrifugoPublishException('centrifugo_invalid_response', true);
        }

        if (!is_array($body)) {
            throw new CentrifugoPublishException('centrifugo_invalid_response', true);
        }

        if (isset($body['error']) && is_array($body['error'])) {
            $errorCode = (int)($body['error']['code'] ?? 0);
            throw new CentrifugoPublishException(
                'centrifugo_error_' . $errorCode,
                $errorCode === 100,
            );
        }

        if (!array_key_exists('result', $body)) {
            throw new CentrifugoPublishException('centrifugo_invalid_response', true);
        }
    }
}

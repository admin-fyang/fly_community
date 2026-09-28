<?php

declare(strict_types=1);

namespace app\response;

use app\Support\Request\RequestContext;
use JsonException;
use support\Response;

/**
 * 统一 API 响应构造器。
 */
final class ApiResponse
{
    /**
     * @param array<string, mixed> $data
     * @param int $status
     * @param string $message 成功文案，默认保持既有接口兼容
     * @return Response
     * @throws JsonException
     */
    public static function success(array $data = [], int $status = 200, string $message = 'success'): Response
    {
        return self::make('OK', $message, $data, $status);
    }

    /**
     * @param string $code
     * @param string $message
     * @param int $status
     * @param array<string, mixed> $data
     * @return Response
     * @throws JsonException
     */
    public static function error(string $code, string $message, int $status, array $data = []): Response
    {
        return self::make($code, $message, $data, $status);
    }

    /**
     * @param string $code
     * @param string $message
     * @param array<string, mixed> $data
     * @param int $status
     * @return Response
     * @throws JsonException
     */
    private static function make(string $code, string $message, array $data, int $status): Response
    {
        $body = json_encode([
            'code' => $code,
            'message' => $message,
            'data' => (object) $data,
            'request_id' => RequestContext::requestId(),
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);

        return new Response($status, ['Content-Type' => 'application/json; charset=utf-8'], $body);
    }
}

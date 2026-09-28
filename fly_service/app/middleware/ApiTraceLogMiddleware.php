<?php

declare(strict_types=1);

namespace app\middleware;

use app\Support\Id\IdGenerator;
use app\Support\Request\RequestContext;
use support\Log;
use app\Support\Logging\SafeLogContext;
use Webman\Http\Request;
use Webman\Http\Response;
use Webman\MiddlewareInterface;

/**
 * 记录 API 请求链路摘要并回传请求 ID。
 */
final class ApiTraceLogMiddleware implements MiddlewareInterface
{
    /**
     * 注入请求ID生成器。
     */
    public function __construct(private readonly IdGenerator $ids)
    {
    }

    /**
     * 创建链路上下文，记录请求摘要并回传请求ID。
     */
    public function process(Request $request, callable $handler): Response
    {
        $startedAt = hrtime(true);
        $requestId = $this->resolveRequestId((string) $request->header('x-request-id', ''));
        RequestContext::setRequestId($requestId);

        $routeName = $request->route?->getName() ?? '';
        Log::info('api.request.started', [
            'request_id' => $requestId,
            'route_name' => $routeName,
            'method' => $request->method(),
            'route_template' => $request->route?->getPath() ?? '[unmatched]',
            'summary' => SafeLogContext::request($request->all()),
            // 'client_ip' => $request->getRemoteIp(),//反代中获取的是127回环地址
            'client_ip' => $request->getRealIp(),
        ]);

        $response = $handler($request);
        $durationMs = round((hrtime(true) - $startedAt) / 1_000_000, 2);
        $level = $durationMs > 500 ? 'warning' : 'info';
        $responseBody = $response->rawBody();
        $decoded = json_decode($responseBody, true);
        $businessCode = is_array($decoded) && is_string($decoded['code'] ?? null)
            ? $decoded['code']
            : null;

        Log::log($level, 'api.request.completed', [
            'request_id' => $requestId,
            'route_name' => $routeName,
            'http_status' => $response->getStatusCode(),
            'business_code' => $businessCode,
            'duration_ms' => $durationMs,
            'request_size' => strlen($request->rawBody()),
            'response_size' => strlen($responseBody),
            'response_ids' => SafeLogContext::summary(is_array($decoded['data']['message'] ?? null)
                ? $decoded['data']['message']
                : (is_array($decoded['data'] ?? null) ? $decoded['data'] : [])),
            'db_query_count' => 0,
            'db_duration_ms' => 0,
        ]);

        return $response->withHeader('X-Request-ID', $requestId);
    }

    /**
     * 接受合法客户端请求ID，否则生成新的ULID格式标识。
     */
    private function resolveRequestId(string $candidate): string
    {
        return preg_match('/^[0-9A-HJKMNP-TV-Z]{26}$/', $candidate) === 1
            ? $candidate
            : $this->ids->requestId();
    }
}

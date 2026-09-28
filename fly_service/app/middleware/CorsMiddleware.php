<?php

declare(strict_types=1);

namespace app\middleware;

use app\response\ApiResponse;
use Webman\Http\Request;
use Webman\Http\Response;
use Webman\MiddlewareInterface;

/**
 * API 跨域中间件，负责校验 Origin 并短路 OPTIONS 预检。
 */
final class CorsMiddleware implements MiddlewareInterface
{
    /**
     * 校验请求来源、处理预检并写入跨域响应头。
     */
    public function process(Request $request, callable $handler): Response
    {
        $origin = (string) $request->header('origin', '');
        $allowedOrigins = config('cors.allowed_origins', []);
        $allowOrigin = self::resolveAllowedOrigin($origin, $allowedOrigins);

        if ($origin !== '' && $allowOrigin === null) {
            return ApiResponse::error('CORS_ORIGIN_DENIED', '请求来源不被允许', 403);
        }

        $response = $request->method() === 'OPTIONS'
            ? new Response(204)
            : $handler($request);

        return self::withCorsHeaders($request, $response);
    }

    /**
     * 为正常响应和异常处理器生成的响应统一附加跨域响应头。
     */
    public static function withCorsHeaders(Request $request, Response $response): Response
    {
        $origin = (string) $request->header('origin', '');
        $allowedOrigins = config('cors.allowed_origins', []);
        $allowOrigin = self::resolveAllowedOrigin($origin, $allowedOrigins);

        if ($allowOrigin !== null && $response->getHeader('Access-Control-Allow-Origin') === null) {
            $response->withHeader('Access-Control-Allow-Origin', $allowOrigin);
            if ($allowOrigin !== '*' && $response->getHeader('Vary') === null) {
                $response->withHeader('Vary', 'Origin');
            }
        }
        if ((bool)config('cors.allow_credentials')
            && $allowOrigin !== null
            && $allowOrigin !== '*'
            && $response->getHeader('Access-Control-Allow-Credentials') === null
        ) {
            $response->withHeader('Access-Control-Allow-Credentials', 'true');
        }

        $headers = [
            'Access-Control-Allow-Methods' => config('cors.allowed_methods'),
            'Access-Control-Allow-Headers' => config('cors.allowed_headers'),
            'Access-Control-Expose-Headers' => config('cors.exposed_headers'),
            'Access-Control-Max-Age' => (string) config('cors.max_age'),
        ];
        foreach ($headers as $name => $value) {
            if ($response->getHeader($name) === null) {
                $response->withHeader($name, $value);
            }
        }
        return $response;
    }

    /**
     * @param list<string> $allowedOrigins
     */
    private static function resolveAllowedOrigin(string $origin, array $allowedOrigins): ?string
    {
        if (in_array('*', $allowedOrigins, true) && !config('cors.allow_credentials')) {
            return '*';
        }

        return in_array($origin, $allowedOrigins, true) ? $origin : null;
    }
}

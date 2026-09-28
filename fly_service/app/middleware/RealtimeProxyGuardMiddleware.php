<?php

declare(strict_types=1);

namespace app\middleware;

use Webman\Http\Request;
use Webman\Http\Response;
use Webman\MiddlewareInterface;

/** 内部实时回调专用认证；密钥只由 Centrifugo 静态请求头提供，不转发客户端同名头。 */
final class RealtimeProxyGuardMiddleware implements MiddlewareInterface
{
    /** 注入独立回调密钥及开关，配置缺失时拒绝所有请求。 */
    public function __construct(private readonly string $secret, private readonly bool $enabled)
    {
    }

    /** 只验证传输来源，用户与会话由应用层验证；不记录带凭证的回调正文。 */
    public function process(Request $request, callable $handler): Response
    {
        if (!$this->enabled || strlen($this->secret) < 32) {
            return new Response(503, [], '');
        }
        if (!hash_equals($this->secret, (string)$request->header('x-realtime-proxy-key', ''))) {
            return new Response(403, [], '');
        }
        if (strlen($request->rawBody()) > 131072) {
            return new Response(413, [], '');
        }
        return $handler($request)->withHeader('Cache-Control', 'no-store');
    }
}

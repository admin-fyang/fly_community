<?php

declare(strict_types=1);

namespace app\Support\Request;

use support\Context;

/**
 * 当前 API 请求上下文。
 *
 * Webman 每次请求都会重置协程上下文，因此不会把用户级状态泄漏到下一请求。
 */
final class RequestContext
{
    private const REQUEST_ID = 'api.request_id';

    /**
     * 将当前请求ID写入Webman协程上下文。
     */
    public static function setRequestId(string $requestId): void
    {
        Context::set(self::REQUEST_ID, $requestId);
    }

    /**
     * 返回当前请求ID；未建立API上下文时返回空字符串。
     */
    public static function requestId(): string
    {
        return (string) Context::get(self::REQUEST_ID, '');
    }
}

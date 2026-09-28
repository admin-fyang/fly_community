<?php

declare(strict_types=1);

namespace app\Support\Auth;

use app\exception\BusinessException;
use support\Context;

/**
 * 当前协程认证上下文访问器。
 */
final class AuthContextHolder
{
    private const AUTH_CONTEXT = 'auth.context';

    /**
     * 将已认证身份写入当前协程上下文。
     */
    public static function set(AuthContext $auth): void
    {
        Context::set(self::AUTH_CONTEXT, $auth);
    }

    /**
     * 读取当前协程认证身份。
     */
    public static function get(): AuthContext
    {
        $auth = Context::get(self::AUTH_CONTEXT);
        if (!$auth instanceof AuthContext) {
            throw new BusinessException('AUTH_CONTEXT_MISSING', '认证上下文不存在', 401);
        }

        return $auth;
    }
}

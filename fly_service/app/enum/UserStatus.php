<?php

declare(strict_types=1);

namespace app\enum;

/**
 * 用户账号状态。
 */
enum UserStatus: int
{
    /** 正常账号，允许登录和使用业务功能。 */
    case Active = 10;

    /** 被管理员或风控长期锁定的账号。 */
    case Locked = 20;

    /** 已申请注销且处于冷静期的账号。 */
    case PendingDelete = 30;

    /** 已完成匿名化的注销账号。 */
    case Deleted = 40;

    /** 被管理员禁用的账号。 */
    case Disabled = 50;

    /**
     * 判断当前账号状态是否允许创建登录会话。
     */
    public function canLogin(): bool
    {
        return $this === self::Active;
    }
}

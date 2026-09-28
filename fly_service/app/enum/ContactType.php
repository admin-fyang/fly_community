<?php

declare(strict_types=1);

namespace app\enum;

/**
 * 登录联系方式类型。
 */
enum ContactType: int
{
    /** 手机号联系方式。 */
    case Phone = 10;

    /** 电子邮箱联系方式。 */
    case Email = 20;
}

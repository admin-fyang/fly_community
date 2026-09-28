<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Enum;

use app\enum\ContactType;

/**
 * 验证码发送渠道。
 */
enum AuthChannel: string
{
    /** 手机短信渠道。 */
    case Phone = 'phone';

    /** 电子邮件渠道。 */
    case Email = 'email';

    /**
     * 返回渠道对应的数据库联系方式类型。
     */
    public function contactType(): ContactType
    {
        return match ($this) {
            self::Phone => ContactType::Phone,
            self::Email => ContactType::Email,
        };
    }
}

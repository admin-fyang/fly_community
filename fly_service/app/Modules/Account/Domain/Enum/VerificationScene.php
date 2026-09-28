<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Enum;

/**
 * 第一阶段允许的验证码场景。
 */
enum VerificationScene: string
{
    /** 手机号注册验证码。 */
    case RegisterPhone = 'register_phone';

    /** 邮箱注册验证码。 */
    case RegisterEmail = 'register_email';

    /** 手机号找回密码验证码。 */
    case ResetPasswordPhone = 'reset_password_phone';

    /** 邮箱找回密码验证码。 */
    case ResetPasswordEmail = 'reset_password_email';

    /**
     * 返回当前验证码场景允许使用的发送渠道。
     */
    public function channel(): AuthChannel
    {
        return match ($this) {
            self::RegisterPhone => AuthChannel::Phone,
            self::RegisterEmail => AuthChannel::Email,
            self::ResetPasswordPhone => AuthChannel::Phone,
            self::ResetPasswordEmail => AuthChannel::Email,
        };
    }

    /** 判断当前场景是否用于新账号注册。 */
    public function isRegistration(): bool
    {
        return $this === self::RegisterPhone || $this === self::RegisterEmail;
    }
}

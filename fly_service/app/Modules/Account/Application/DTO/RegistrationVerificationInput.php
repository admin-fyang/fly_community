<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\DTO;

use app\Modules\Account\Domain\Enum\AuthChannel;

/**
 * 注册时单个联系方式的验证码输入。
 */
final readonly class RegistrationVerificationInput
{
    /**
     * 保存已经过 HTTP 白名单和基础格式校验的验证码数据。
     */
    public function __construct(
        public AuthChannel $channel,
        public string $account,
        public ?string $countryCode,
        public string $verificationRequestId,
        public string $code,
    ) {
    }
}

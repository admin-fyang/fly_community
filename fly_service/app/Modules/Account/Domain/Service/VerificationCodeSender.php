<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Service;

use app\Modules\Account\Domain\ValueObject\NormalizedContact;

interface VerificationCodeSender
{
    /**
     * 将验证码发送到指定的规范化联系方式。
     */
    public function send(NormalizedContact $contact, string $code): void;
}

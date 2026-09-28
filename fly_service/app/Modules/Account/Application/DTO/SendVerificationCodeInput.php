<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\DTO;

use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\Enum\VerificationScene;

/**
 * 发送验证码用例输入。
 */
final readonly class SendVerificationCodeInput
{
    /**
     * 创建发送验证码用例输入。
     */
    public function __construct(
        public VerificationScene $scene,
        public AuthChannel $channel,
        public string $target,
        public ?string $countryCode,
        public string $clientIp,
    ) {
    }
}

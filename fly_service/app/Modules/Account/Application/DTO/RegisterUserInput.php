<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\DTO;

use app\Modules\Account\Domain\DTO\DeviceData;

/**
 * 用户名密码注册用例输入。
 */
final readonly class RegisterUserInput
{
    /**
     * 创建注册用例输入，保存完成注册所需的白名单字段。
     */
    public function __construct(
        public string $username,
        public string $nickname,
        public string $password,
        public ?string $inviteCode,
        public ?RegistrationVerificationInput $phoneVerification,
        public ?RegistrationVerificationInput $emailVerification,
        public DeviceData $device,
        public string $clientIp,
        public string $userAgent,
    ) {
    }
}

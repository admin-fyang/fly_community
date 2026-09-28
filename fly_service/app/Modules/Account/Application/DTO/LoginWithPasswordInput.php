<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\DTO;

use app\Modules\Account\Domain\DTO\DeviceData;

/**
 * 密码登录用例输入。
 */
final readonly class LoginWithPasswordInput
{
    /**
     * 创建密码登录用例输入，隔离HTTP请求对象。
     */
    public function __construct(
        public string $account,
        public ?string $countryCode,
        public string $password,
        public DeviceData $device,
        public string $clientIp,
        public string $userAgent,
    ) {
    }
}

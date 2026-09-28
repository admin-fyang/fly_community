<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\DTO;

/**
 * 登录设备的白名单字段。
 */
final readonly class DeviceData
{
    /**
     * 创建经过HTTP层白名单校验的设备数据。
     */
    public function __construct(
        public string $deviceId,
        public string $platform,
        public string $deviceName,
        public ?string $appVersion,
    ) {
    }
}

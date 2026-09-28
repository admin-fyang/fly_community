<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\ValueObject;

use app\Modules\Account\Domain\Enum\AuthChannel;

/**
 * 已完成格式规范化的登录联系方式。
 */
final readonly class NormalizedContact
{
    /**
     * 创建规范化后的手机号或邮箱值对象。
     */
    public function __construct(
        public AuthChannel $channel,
        public string $value,
        public string $masked,
    ) {
    }
}

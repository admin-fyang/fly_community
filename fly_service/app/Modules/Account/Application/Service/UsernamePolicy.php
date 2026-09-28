<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Service;

use app\exception\BusinessException;
use app\Support\Identity\ReservedIdentifierPolicy;

/**
 * 统一注册和公开可用性检查使用的用户名规范。
 */
final class UsernamePolicy
{
    /** @var list<string> 禁止普通用户占用的系统保留用户名。 */
    private const RESERVED = [
        'admin',
        'administrator',
        'system',
        'support',
        'service',
        'official',
    ];

    /** 注入用户和群共用的运营保留关键字规则。 */
    public function __construct(private readonly ReservedIdentifierPolicy $reserved) {}

    /**
     * 去除首尾空白和可选前导@、转为小写并校验稳定格式。
     */
    public function normalize(string $value): string
    {
        $username = strtolower(ltrim(trim($value), '@'));
        if (
            preg_match('/\A[a-z][a-z0-9_]{4,31}\z/', $username) !== 1
            || in_array($username, self::RESERVED, true)
            || $this->reserved->containsReservedKeyword($username)
        ) {
            throw new BusinessException('USERNAME_INVALID', '用户名格式不正确或属于保留词', 422);
        }

        return $username;
    }
}

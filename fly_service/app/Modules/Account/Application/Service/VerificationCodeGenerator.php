<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Service;

use RuntimeException;

/**
 * 生产生成随机验证码，local/test可显式配置固定验证码。
 */
final class VerificationCodeGenerator
{
    /**
     * 配置验证码驱动及仅限调试环境的固定验证码。
     */
    public function __construct(
        private readonly bool $debug,
        private readonly string $driver,
        private readonly string $fixedCode,
    ) {
    }

    /**
     * 生成六位验证码，生产环境默认使用安全随机数。
     */
    public function generate(): string
    {
        if ($this->driver === 'fixed') {
            if (!$this->debug || preg_match('/^[0-9]{6}$/', $this->fixedCode) !== 1) {
                throw new RuntimeException('固定验证码仅允许在调试环境使用，且必须为6位数字');
            }
            return $this->fixedCode;
        }

        return (string) random_int(100000, 999999);
    }
}

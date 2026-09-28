<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Security;

use app\Modules\Account\Domain\Service\VerificationCodeSender;
use app\Modules\Account\Domain\ValueObject\NormalizedContact;
use RuntimeException;

/**
 * 本地和测试环境固定验证码发送器。
 *
 * 不发送、不记录验证码；开发者通过环境变量预先获知固定值。
 */
final class FixedVerificationCodeSender implements VerificationCodeSender
{
    /**
     * 注入当前环境是否允许调试验证码。
     */
    public function __construct(private readonly bool $debug)
    {
    }

    /**
     * 调试环境不执行外部发送；生产环境未配置供应商时拒绝继续。
     */
    public function send(NormalizedContact $contact, string $code): void
    {
        if (!$this->debug) {
            throw new RuntimeException('生产环境未配置验证码供应商');
        }
    }
}

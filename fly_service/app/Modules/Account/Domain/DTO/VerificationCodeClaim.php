<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\DTO;

use app\Modules\Account\Domain\Enum\VerificationScene;

/**
 * 待原子消费的验证码声明，不包含联系方式原文。
 */
final readonly class VerificationCodeClaim
{
    /**
     * 创建验证码请求、场景、目标摘要和验证码摘要的绑定声明。
     */
    public function __construct(
        public string $requestId,
        public VerificationScene $scene,
        public string $targetHash,
        public string $codeHash,
    ) {
    }
}

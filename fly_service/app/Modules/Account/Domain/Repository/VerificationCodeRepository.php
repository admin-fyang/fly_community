<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Repository;

use app\Modules\Account\Domain\DTO\VerificationCodeClaim;
use app\Modules\Account\Domain\Enum\VerificationScene;

interface VerificationCodeRepository
{
    /**
     * 原子预留验证码请求并占用发送频率额度。
     */
    public function reserve(
        string $requestId,
        VerificationScene $scene,
        string $targetHash,
        string $codeHash,
        string $ipHash,
        int $ttlSeconds,
        int $resendSeconds,
    ): void;

    /**
     * 在发送成功后激活验证码。
     */
    public function activate(string $requestId): void;

    /**
     * 发送失败时释放尚未激活的验证码请求。
     */
    public function cancel(string $requestId, VerificationScene $scene, string $targetHash): void;

    /**
     * 原子校验并一次性消费验证码。
     */
    public function consume(
        string $requestId,
        VerificationScene $scene,
        string $targetHash,
        string $codeHash,
        int $maxAttempts,
    ): void;

    /**
     * 原子校验并一次性消费一组验证码，任一项失败时不得消费其它项。
     *
     * @param list<VerificationCodeClaim> $claims
     */
    public function consumeAll(array $claims, int $maxAttempts): void;
}

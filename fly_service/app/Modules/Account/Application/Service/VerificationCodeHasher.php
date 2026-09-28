<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Service;

use RuntimeException;

/**
 * 验证码只以请求ID绑定的HMAC形式进入Redis。
 */
final class VerificationCodeHasher
{
    private readonly string $key;

    /**
     * 解码并校验验证码专用HMAC密钥。
     */
    public function __construct(string $keyBase64)
    {
        $key = base64_decode($keyBase64, true);
        if ($key === false || strlen($key) !== 32) {
            throw new RuntimeException('AUTH_VERIFICATION_CODE_KEY 必须是 Base64 编码的 32 字节密钥');
        }
        $this->key = $key;
    }

    /**
     * 将验证码与请求ID绑定后生成不可逆摘要。
     */
    public function hash(string $requestId, string $code): string
    {
        return hash_hmac('sha256', $requestId . ':' . $code, $this->key);
    }
}

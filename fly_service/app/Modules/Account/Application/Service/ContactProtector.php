<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Service;

use app\Modules\Account\Domain\ValueObject\NormalizedContact;
use app\Modules\Account\Domain\ValueObject\ProtectedContact;
use RuntimeException;

/**
 * 对联系方式生成可查询 HMAC 和可轮换密文。
 */
final class ContactProtector
{
    private readonly string $lookupKey;
    private readonly string $encryptionKey;

    /**
     * 解码并校验联系方式查询密钥和加密密钥。
     */
    public function __construct(string $lookupKeyBase64, string $encryptionKeyBase64)
    {
        $this->lookupKey = $this->decodeKey($lookupKeyBase64, 'AUTH_CONTACT_LOOKUP_KEY');
        $this->encryptionKey = $this->decodeKey($encryptionKeyBase64, 'AUTH_CONTACT_ENCRYPTION_KEY');
    }

    /**
     * 生成联系方式查询HMAC、密文和脱敏值。
     */
    public function protect(NormalizedContact $contact): ProtectedContact
    {
        $type = $contact->channel->contactType();
        $hash = hash_hmac('sha256', $type->value . ':' . $contact->value, $this->lookupKey, true);
        $nonce = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt(
            $contact->value,
            'aes-256-gcm',
            $this->encryptionKey,
            OPENSSL_RAW_DATA,
            $nonce,
            $tag,
            '',
            16,
        );

        if ($ciphertext === false) {
            throw new RuntimeException('联系方式加密失败');
        }

        return new ProtectedContact(
            $type,
            $hash,
            $nonce . $tag . $ciphertext,
            1,
            $contact->masked,
        );
    }

    /**
     * 生成验证码目标使用的不可逆十六进制摘要。
     */
    public function targetHash(NormalizedContact $contact): string
    {
        return bin2hex(hash_hmac(
            'sha256',
            $contact->channel->contactType()->value . ':' . $contact->value,
            $this->lookupKey,
            true,
        ));
    }

    /**
     * 解密已持久化的联系方式。
     *
     * 仅供明确获授权的服务端业务流程使用；调用方不得把明文写入日志、审计上下文或缓存。
     */
    public function decrypt(string $ciphertext): string
    {
        $plain = openssl_decrypt(
            substr($ciphertext, 28),
            'aes-256-gcm',
            $this->encryptionKey,
            OPENSSL_RAW_DATA,
            substr($ciphertext, 0, 12),
            substr($ciphertext, 12, 16),
        );
        if ($plain === false) {
            throw new RuntimeException('联系方式解密失败');
        }

        return $plain;
    }

    /**
     * 为IP或其他限流标识生成不可逆摘要。
     */
    public function opaqueHash(string $value): string
    {
        return bin2hex(hash_hmac('sha256', $value, $this->lookupKey, true));
    }

    /**
     * 解码32字节Base64密钥，配置错误时立即失败。
     */
    private function decodeKey(string $encoded, string $name): string
    {
        $key = base64_decode($encoded, true);
        if ($key === false || strlen($key) !== 32) {
            throw new RuntimeException($name . ' 必须是 Base64 编码的 32 字节密钥');
        }

        return $key;
    }
}

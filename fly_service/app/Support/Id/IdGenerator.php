<?php

declare(strict_types=1);

namespace app\Support\Id;

/**
 * 生成不依赖数据库的安全随机标识。
 */
final class IdGenerator
{
    private const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    /**
     * 生成符合RFC 4122格式的随机UUID v4。
     */
    public function uuidV4(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        $hex = bin2hex($bytes);

        return sprintf(
            '%s-%s-%s-%s-%s',
            substr($hex, 0, 8),
            substr($hex, 8, 4),
            substr($hex, 12, 4),
            substr($hex, 16, 4),
            substr($hex, 20, 12),
        );
    }

    /**
     * 生成不可枚举的Crockford Base32公开用户ID。
     */
    public function publicId(int $length = 12): string
    {
        return $this->randomCrockford($length);
    }

    /**
     * 生成用户专属邀请码。
     */
    public function inviteCode(int $length = 10): string
    {
        return $this->randomCrockford($length);
    }

    /**
     * 生成带毫秒时间前缀的26位请求链路ID。
     */
    public function requestId(): string
    {
        $milliseconds = (int) floor(microtime(true) * 1000);
        $time = '';
        for ($index = 0; $index < 10; $index++) {
            $time = self::CROCKFORD[$milliseconds % 32] . $time;
            $milliseconds = intdiv($milliseconds, 32);
        }

        return $time . $this->randomCrockford(16);
    }

    /**
     * 使用安全随机源生成指定长度的Crockford Base32字符串。
     */
    private function randomCrockford(int $length): string
    {
        $result = '';
        for ($index = 0; $index < $length; $index++) {
            $result .= self::CROCKFORD[random_int(0, 31)];
        }

        return $result;
    }
}

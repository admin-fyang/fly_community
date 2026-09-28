<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Service;

use app\exception\BusinessException;
use RuntimeException;

/**
 * 统一密码强度、Argon2id 参数和防时序枚举的虚拟校验。
 */
final class PasswordHasher
{
    private const OPTIONS = [
        'memory_cost' => 65_536,
        'time_cost' => 3,
        'threads' => 1,
    ];

    private readonly string $dummyHash;

    /**
     * 为当前Worker生成防账号枚举的虚拟密码哈希。
     */
    public function __construct()
    {
        $hash = password_hash(bin2hex(random_bytes(16)), PASSWORD_ARGON2ID, self::OPTIONS);
        if ($hash === false) {
            throw new RuntimeException('Argon2id 初始化失败');
        }
        $this->dummyHash = $hash;
    }

    /**
     * 校验密码长度、字节数以及字母数字组合要求。
     */
    public function assertStrong(string $password): void
    {
        $characters = mb_strlen($password);
        if (
            $characters < 8
            || $characters > 64
            || strlen($password) > 128
            || preg_match('/[A-Za-z]/', $password) !== 1
            || preg_match('/[0-9]/', $password) !== 1
        ) {
            throw new BusinessException('PASSWORD_TOO_WEAK', '密码必须为8至64个字符，并同时包含字母和数字', 400);
        }
    }

    /**
     * 使用固定安全参数生成Argon2id密码哈希。
     */
    public function hash(string $password): string
    {
        $hash = password_hash($password, PASSWORD_ARGON2ID, self::OPTIONS);
        if ($hash === false) {
            throw new RuntimeException('密码哈希失败');
        }

        return $hash;
    }

    /**
     * 校验密码；用户不存在时使用虚拟哈希保持相近计算成本。
     */
    public function verify(string $password, ?string $hash): bool
    {
        return password_verify($password, $hash ?? $this->dummyHash);
    }
}

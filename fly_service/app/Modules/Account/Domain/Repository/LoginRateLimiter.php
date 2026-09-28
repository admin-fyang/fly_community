<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Repository;

interface LoginRateLimiter
{
    /**
     * 检查身份与IP组合是否仍允许尝试登录。
     */
    public function assertAllowed(string $identityHash, string $ipHash): void;

    /**
     * 原子增加登录失败计数并设置窗口过期时间。
     */
    public function recordFailure(string $identityHash, string $ipHash): void;

    /**
     * 登录成功后清除该身份相关的失败计数。
     */
    public function clear(string $identityHash, string $ipHash): void;
}

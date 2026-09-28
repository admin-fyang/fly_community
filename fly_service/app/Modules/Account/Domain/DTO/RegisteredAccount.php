<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\DTO;

/**
 * 注册事务一次性创建的用户与登录会话。
 */
final readonly class RegisteredAccount
{
    /**
     * 聚合注册事务创建的用户和首个会话。
     */
    public function __construct(
        public AuthenticatedUser $user,
        public CreatedSession $session,
    ) {
    }
}

<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\UseCase;

use app\Modules\Account\Application\SessionRevocationService;
use app\Support\Auth\AuthContext;

/** 当前会话退出复用单会话撤销事务，保留同安装实例的其他会话。 */
final class LogoutCurrentSession
{
    /** 注入统一撤销事务。 */
    public function __construct(private readonly SessionRevocationService $revocation)
    {
    }

    /** 当前退出入口允许撤销自身，设备管理入口仍保护当前会话。 */
    public function execute(AuthContext $auth, string $ip, string $userAgent): void
    {
        $this->revocation->revoke($auth, $auth->sessionId, $ip, $userAgent, false);
    }
}

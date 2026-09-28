<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Query;

use app\Modules\Account\Application\Service\UsernamePolicy;
use app\Modules\Account\Domain\Repository\AuthRepository;

/**
 * 公开查询用户名当前是否可用于注册。
 *
 * 结果仅是即时提示；最终占用结果仍由注册事务和数据库唯一索引决定。
 */
final class UsernameAvailability
{
    /**
     * 注入用户名规则和只读认证仓储。
     */
    public function __construct(
        private readonly UsernamePolicy $usernames,
        private readonly AuthRepository $auth,
    ) {
    }

    /**
     * 返回规范化用户名及查询时刻的可用状态。
     *
     * @return array{username:string,available:bool}
     */
    public function check(string $input): array
    {
        $username = $this->usernames->normalize($input);

        return [
            'username' => '@' . $username,
            'available' => !$this->auth->usernameExists($username),
        ];
    }
}

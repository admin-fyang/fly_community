<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\Query\UsernameAvailability;
use app\response\ApiResponse;
use support\Response;

/**
 * 无需登录的用户名可用性检查接口。
 */
final class UsernameAvailabilityController
{
    /**
     * 注入用户名可用性查询服务。
     */
    public function __construct(private readonly UsernameAvailability $availability)
    {
    }

    /**
     * 校验路径中的用户名并返回当前可用状态。
     */
    public function show(string $username): Response
    {
        return ApiResponse::success($this->availability->check($username));
    }
}

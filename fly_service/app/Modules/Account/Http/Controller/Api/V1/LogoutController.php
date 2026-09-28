<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\UseCase\LogoutCurrentSession;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/**
 * 当前设备退出登录接口。
 */
final class LogoutController
{
    /**
     * 注入退出登录用例。
     */
    public function __construct(private readonly LogoutCurrentSession $useCase)
    {
    }

    /**
     * 撤销当前 Access Token 对应的会话。
     */
    public function logout(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        $this->useCase->execute($auth, $request->getRemoteIp(), (string) $request->header('user-agent', ''));
        return ApiResponse::success();
    }
}

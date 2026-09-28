<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\UseCase\AccountSecurityService;
use app\Modules\Account\Http\Request\AccountSecurityRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/** 密码与账号注销API控制器。 */
final class AccountSecurityController
{
    /** 注入账号安全用例与HTTP输入校验器。 */
    public function __construct(private readonly AccountSecurityService $service, private readonly AccountSecurityRequest $validator)
    {
    }

    /** 使用已消费验证码重置密码并撤销全部会话。 */
    public function resetPassword(Request $request): Response
    {
        return ApiResponse::success($this->service->resetPassword($this->validator->resetPassword($request), $request->getRemoteIp(), (string)$request->header('user-agent', '')));
    }

    /** 校验当前密码并修改密码。 */
    public function changePassword(Request $request): Response
    {
        return ApiResponse::success($this->service->changePassword(AuthContextHolder::get(), $this->validator->changePassword($request), $request->getRemoteIp(), (string)$request->header('user-agent', '')));
    }

    /** 使用当前密码申请30天冷静期注销。 */
    public function requestDeletion(Request $request): Response
    {
        return ApiResponse::success($this->service->requestDeletion(AuthContextHolder::get(), $this->validator->currentPassword($request), $request->getRemoteIp(), (string)$request->header('user-agent', '')), 201);
    }

    /** 在冷静期到期前取消注销。 */
    public function cancelDeletion(Request $request, string $id): Response
    {
        return ApiResponse::success($this->service->cancelDeletion(AuthContextHolder::get(), $this->validator->deletionId($id), $request->getRemoteIp(), (string)$request->header('user-agent', '')));
    }
}

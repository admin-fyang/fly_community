<?php

declare(strict_types=1);

namespace app\Modules\User\Http\Controller\Api\V1;

use app\Modules\User\Application\UserProfileService;
use app\Modules\User\Http\Request\UserProfileRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/**
 * 当前用户资料接口。
 */
final class UserProfileController
{
    /**
     * 注入用户资料服务与请求验证器。
     */
    public function __construct(
        private readonly UserProfileService $profiles,
        private readonly UserProfileRequest $validator,
    ) {
    }

    /**
     * 查看当前用户完整资料。
     */
    public function show(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        return ApiResponse::success($this->profiles->show($auth->userId));
    }

    /**
     * 使用乐观锁修改当前用户资料。
     */
    public function update(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        return ApiResponse::success($this->profiles->update($auth->userId, $this->validator->update($request)));
    }

    /**
     * 绑定已完成上传的头像资源。
     */
    public function avatar(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        return ApiResponse::success($this->profiles->bindAvatar($auth->userId, $this->validator->avatarResourceId($request)));
    }
}

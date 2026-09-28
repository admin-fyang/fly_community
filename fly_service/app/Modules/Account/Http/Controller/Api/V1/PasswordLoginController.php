<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\UseCase\LoginWithPassword;
use app\Modules\Account\Http\Request\AuthRequestValidator;
use app\response\ApiResponse;
use support\Request;
use support\Response;

/**
 * 手机号、邮箱或用户名密码登录接口。
 */
final class PasswordLoginController
{
    /**
     * 注入密码登录用例和HTTP输入校验器。
     */
    public function __construct(
        private readonly LoginWithPassword $useCase,
        private readonly AuthRequestValidator $validator,
    ) {
    }

    /**
     * 处理手机号、邮箱或用户名密码登录请求。
     */
    public function login(Request $request): Response
    {
        return ApiResponse::success(
            $this->useCase->execute($this->validator->passwordLogin($request))->toArray(),
        );
    }
}

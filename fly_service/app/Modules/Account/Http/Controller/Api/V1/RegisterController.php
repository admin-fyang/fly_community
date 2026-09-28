<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\UseCase\RegisterUser;
use app\Modules\Account\Http\Request\AuthRequestValidator;
use app\response\ApiResponse;
use support\Request;
use support\Response;

/**
 * 用户名密码注册接口。
 */
final class RegisterController
{
    /**
     * 注入注册用例和HTTP输入校验器。
     */
    public function __construct(
        private readonly RegisterUser         $useCase,
        private readonly AuthRequestValidator $validator,
    )
    {
    }

    /**
     * 处理用户名、昵称、密码及按配置启用的联系方式验证请求。
     */
    public function register(Request $request): Response
    {
        return ApiResponse::success(
            $this->useCase->execute($this->validator->registration($request))->toArray(),
            201,
        );
    }
}

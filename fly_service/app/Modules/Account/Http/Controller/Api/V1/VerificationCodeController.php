<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Controller\Api\V1;

use app\Modules\Account\Application\UseCase\SendVerificationCode;
use app\Modules\Account\Http\Request\AuthRequestValidator;
use app\response\ApiResponse;
use support\Request;
use support\Response;

/**
 * 注册验证码接口。
 */
final class VerificationCodeController
{
    /**
     * 注入发送验证码用例和HTTP输入校验器。
     */
    public function __construct(
        private readonly SendVerificationCode $useCase,
        private readonly AuthRequestValidator $validator,
    ) {
    }

    /**
     * 处理注册验证码获取请求。
     */
    public function send(Request $request): Response
    {
        return ApiResponse::success(
            $this->useCase->execute($this->validator->verificationCode($request)),
            201,
        );
    }
}

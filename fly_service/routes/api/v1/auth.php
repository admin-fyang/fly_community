<?php

declare(strict_types=1);

use app\Modules\Account\Http\Controller\Api\V1\PasswordLoginController;
use app\Modules\Account\Http\Controller\Api\V1\RegisterController;
use app\Modules\Account\Http\Controller\Api\V1\VerificationCodeController;
use app\Modules\Account\Http\Controller\Api\V1\UsernameAvailabilityController;
use app\Modules\Account\Http\Controller\Api\V1\AccountSecurityController;
use app\middleware\ApiTraceLogMiddleware;
use app\middleware\CorsMiddleware;
use Webman\Route;

Route::group('/api/v1', function (): void {
    Route::post('/auth/verification-codes', [VerificationCodeController::class, 'send'])
        ->name('api.v1.认证.验证码.发送');

    Route::post('/auth/register', [RegisterController::class, 'register'])
        ->name('api.v1.认证.注册');

    Route::get('/usernames/{username}/availability', [UsernameAvailabilityController::class, 'show'])
        ->name('api.v1.用户.用户名.检查可用');

    Route::post('/auth/login/password', [PasswordLoginController::class, 'login'])
        ->name('api.v1.认证.密码登录');

    Route::post('/auth/password/reset', [AccountSecurityController::class, 'resetPassword'])
        ->name('api.v1.认证.密码.重置');

})->middleware([
    ApiTraceLogMiddleware::class,
    CorsMiddleware::class,
]);

<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\AuthMiddleware;
use app\middleware\CorsMiddleware;
use app\Modules\Account\Http\Controller\Api\V1\AccountSecurityController;
use Webman\Route;

Route::group('/api/v1', static function (): void {
    Route::patch('/users/me/password', [AccountSecurityController::class, 'changePassword'])->name('api.v1.账号安全.密码.修改');
    Route::post('/users/me/deletion-requests', [AccountSecurityController::class, 'requestDeletion'])->name('api.v1.账号安全.注销.申请');
    Route::post('/users/me/deletion-requests/{id}/cancel', [AccountSecurityController::class, 'cancelDeletion'])->name('api.v1.账号安全.注销.取消');
})->middleware([ApiTraceLogMiddleware::class, CorsMiddleware::class, AuthMiddleware::class]);

<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\AuthMiddleware;
use app\middleware\CorsMiddleware;
use app\Modules\Account\Http\Controller\Api\V1\LogoutController;
use app\Modules\File\Http\Controller\Api\V1\FileUploadController;
use app\Modules\User\Http\Controller\Api\V1\UserProfileController;
use Webman\Route;

Route::group('/api/v1', function (): void {
    Route::get('/auth/sessions', [\app\Modules\Account\Http\Controller\Api\V1\DeviceSessionController::class, 'index'])
        ->name('api.v1.认证.登录会话.列表');
    Route::delete('/auth/sessions/{session_id}', [\app\Modules\Account\Http\Controller\Api\V1\DeviceSessionController::class, 'delete'])
        ->name('api.v1.认证.登录会话.撤销');

    Route::post('/auth/logout', [LogoutController::class, 'logout'])
        ->name('api.v1.认证.退出.当前设备');

    Route::get('/users/me', [UserProfileController::class, 'show'])
        ->name('api.v1.用户.当前用户.查看');

    Route::patch('/users/me', [UserProfileController::class, 'update'])
        ->name('api.v1.用户.当前用户.修改');

    Route::post('/users/me/avatar', [UserProfileController::class, 'avatar'])
        ->name('api.v1.用户.头像.绑定');

    Route::post('/files/avatar/upload-credentials', [FileUploadController::class, 'credential'])
        ->name('api.v1.文件.头像.上传凭证');

    Route::post('/files/message/upload-credentials', [FileUploadController::class, 'messageCredential'])
        ->name('api.v1.文件.聊天附件.上传凭证');

    Route::post('/files/{resource_id}/complete', [FileUploadController::class, 'complete'])
        ->name('api.v1.文件.上传.完成');

    Route::post('/files/{resource_id}/multipart/parts/credentials', [FileUploadController::class, 'multipartPartCredentials'])
        ->name('api.v1.文件.分片上传.分片凭证');

    Route::get('/files/{resource_id}/multipart', [FileUploadController::class, 'multipartStatus'])
        ->name('api.v1.文件.分片上传.查询');

    Route::post('/files/{resource_id}/multipart/complete', [FileUploadController::class, 'multipartComplete'])
        ->name('api.v1.文件.分片上传.完成');

    Route::delete('/files/{resource_id}/multipart', [FileUploadController::class, 'multipartAbort'])
        ->name('api.v1.文件.分片上传.取消');
})->middleware([
    ApiTraceLogMiddleware::class,
    CorsMiddleware::class,
    AuthMiddleware::class,
]);

<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\AuthMiddleware;
use app\middleware\CorsMiddleware;
use app\Modules\Notification\Http\Controller\Api\V1\NotificationController;
use Webman\Route;

Route::group('/api/v1/notifications', static function (): void {
    Route::get('', [NotificationController::class, 'list'])
        ->name('api.v1.系统通知.获取通知列表');

    Route::get('/unread-count', [NotificationController::class, 'unreadCount'])
        ->name('api.v1.系统通知.获取未读数量');

    Route::post('/{notification_id}/read', [NotificationController::class, 'read'])
        ->name('api.v1.系统通知.标记单条已读');

    Route::post('/read-all', [NotificationController::class, 'readAll'])
        ->name('api.v1.系统通知.标记全部已读');

    Route::post('/{notification_id}/handle', [NotificationController::class, 'handle'])
        ->name('api.v1.系统通知.处理通知');

    Route::delete('/{notification_id}', [NotificationController::class, 'deleteForMe'])
        ->name('api.v1.系统通知.仅对我删除');
})->middleware([
    ApiTraceLogMiddleware::class,
    CorsMiddleware::class,
    AuthMiddleware::class,
]);

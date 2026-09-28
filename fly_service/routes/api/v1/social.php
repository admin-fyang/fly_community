<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\AuthMiddleware;
use app\middleware\CorsMiddleware;
use app\Modules\Contact\Http\Controller\Api\V1\ContactController;
use Webman\Route;

Route::group('/api/v1', static function (): void {
    Route::get('/contacts', [ContactController::class, 'list'])
        ->name('api.v1.联系人.获取列表');
    Route::get('/users/search', [ContactController::class, 'searchUsers'])
        ->name('api.v1.用户.搜索用户');
    Route::get('/users/{user_id}/profile', [ContactController::class, 'profile'])
        ->name('api.v1.用户.查看公开资料');
    Route::post('/friend-requests', [ContactController::class, 'requestFriend'])
        ->name('api.v1.联系人.发起好友申请');
    Route::patch('/contacts/{user_id}/remark', [ContactController::class, 'updateRemark'])
        ->name('api.v1.联系人.修改备注');
    Route::patch('/contacts/{user_id}/settings', [ContactController::class, 'updateSettings'])
        ->name('api.v1.联系人.修改设置');
    Route::delete('/contacts/{user_id}', [ContactController::class, 'delete'])
        ->name('api.v1.联系人.删除联系人');
    Route::post('/contacts/{user_id}/block', [ContactController::class, 'block'])
        ->name('api.v1.联系人.拉黑用户');
    Route::delete('/contacts/{user_id}/block', [ContactController::class, 'unblock'])
        ->name('api.v1.联系人.取消拉黑');

})->middleware([
    ApiTraceLogMiddleware::class,
    CorsMiddleware::class,
    AuthMiddleware::class,
]);

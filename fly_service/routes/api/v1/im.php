<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\AuthMiddleware;
use app\middleware\CorsMiddleware;
use app\Modules\Im\Http\Controller\Api\V1\ImDirectoryController;
use app\Modules\Im\Http\Controller\Api\V1\ImMessageController;
use Webman\Route;

// 社区版仅开放单聊、会话和基础同步接口。
Route::group('/api/v1/im', static function (): void {
    Route::post('/messages', [ImMessageController::class, 'sendMessage'])->name('api.v1.im.message.send');
    Route::post('/conversations/single', [ImMessageController::class, 'resolveSingleConversation'])->name('api.v1.im.single.resolve');
    Route::get('/conversations', [ImMessageController::class, 'listConversations'])->name('api.v1.im.conversation.list');
    Route::get('/conversations/{conversation_id}/messages', [ImMessageController::class, 'listMessages'])->name('api.v1.im.message.history');
    Route::get('/sync', [ImMessageController::class, 'sync'])->name('api.v1.im.sync');
    Route::post('/sync/ack', [ImMessageController::class, 'acknowledgeSync'])->name('api.v1.im.sync.ack');
    Route::get('/directory/bootstrap', [ImDirectoryController::class, 'bootstrap'])->name('api.v1.im.directory.bootstrap');
    Route::post('/directory/user-briefs/changes', [ImDirectoryController::class, 'changedUserBriefs'])->name('api.v1.im.directory.changes');
    Route::post('/centrifugo/token', [ImMessageController::class, 'createCentrifugoToken'])->name('api.v1.im.realtime.token');
    Route::post('/conversations/{conversation_id}/read', [ImMessageController::class, 'markRead'])->name('api.v1.im.conversation.read');
    Route::post('/messages/{message_id}/recall', [ImMessageController::class, 'recallMessage'])->name('api.v1.im.message.recall');
    Route::delete('/messages/{message_id}', [ImMessageController::class, 'deleteMessageForMe'])->name('api.v1.im.message.delete');
    Route::delete('/conversations', [ImMessageController::class, 'deleteConversation'])->name('api.v1.im.conversation.delete');
})->middleware([ApiTraceLogMiddleware::class, CorsMiddleware::class, AuthMiddleware::class]);

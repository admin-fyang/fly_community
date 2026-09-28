<?php

declare(strict_types=1);

use app\Modules\Account\Http\Controller\Api\V1\RealtimeSessionController;
use app\middleware\RealtimeProxyGuardMiddleware;
use Webman\Route;

Route::group('/internal/v1/realtime', static function (): void {
    Route::post('/connect', [RealtimeSessionController::class, 'connect'])->name('internal.v1.realtime.connect');
    Route::post('/refresh', [RealtimeSessionController::class, 'refresh'])->name('internal.v1.realtime.refresh');
})->middleware([RealtimeProxyGuardMiddleware::class]);

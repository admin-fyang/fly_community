<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\CorsMiddleware;
use Webman\Route;

Route::group('/api/v1', function (): void {
    Route::options('/{path:.+}', static fn () => response('', 204))
        ->name('api.v1.跨域.预检');
})->middleware([
    ApiTraceLogMiddleware::class,
    CorsMiddleware::class,
]);

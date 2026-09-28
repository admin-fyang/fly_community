<?php

declare(strict_types=1);

use app\middleware\ApiTraceLogMiddleware;
use app\middleware\CorsMiddleware;
use app\Modules\System\Http\Controller\Api\V1\SystemConfigController;
use app\Modules\System\Http\Controller\Api\V1\SystemContentController;
use Webman\Route;

Route::group('/api/v1/system', static function (): void {
    Route::get('/config', [SystemConfigController::class, 'show'])
        ->name('api.v1.系统.配置.查看');
    Route::get('/content-pages/{slug}', [SystemContentController::class, 'page'])
        ->name('api.v1.系统.内容页.查看');
})->middleware([
    ApiTraceLogMiddleware::class,
    CorsMiddleware::class,
]);

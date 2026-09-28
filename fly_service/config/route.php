<?php
/**
 * This file is part of webman.
 *
 * Licensed under The MIT License
 * For full copyright and license information, please see the MIT-LICENSE.txt
 * Redistributions of files must retain the above copyright notice.
 *
 * @author    walkor<walkor@workerman.net>
 * @copyright walkor<walkor@workerman.net>
 * @link      http://www.workerman.net/
 * @license   http://www.opensource.org/licenses/mit-license.php MIT License
 */

use Webman\Route;
use support\Response;
Route::disableDefaultRoute();

Route::get('/',[\app\controller\IndexController::class,'index']);

require base_path('routes/api/v1/cors.php');
require base_path('routes/api/v1/auth.php');
require base_path('routes/api/v1/system.php');
require base_path('routes/api/v1/protected.php');
require base_path('routes/api/v1/non_im.php');
require base_path('routes/api/v1/im.php');
require base_path('routes/api/v1/notifications.php');
require base_path('routes/api/v1/social.php');


//404路由
// 未命中入口也必须经过来源校验及链路日志，保留既有404业务码与文案。
Route::fallback(function(){
    return new Response(404, ['Content-Type' => 'application/json'], json_encode([
        'code' => 404,
        'message' => '404 not found',
        'request_id' => \app\Support\Request\RequestContext::requestId(),
    ]));
})->middleware([\app\middleware\ApiTraceLogMiddleware::class, \app\middleware\CorsMiddleware::class]);

// 内部回调使用专用来源认证和供应商协议，不记录包含凭证的请求正文。
require base_path('routes/internal/realtime.php');

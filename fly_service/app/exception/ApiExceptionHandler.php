<?php

declare(strict_types=1);

namespace app\exception;

use app\middleware\CorsMiddleware;
use app\response\ApiResponse;
use app\Support\Request\RequestContext;
use support\Log;
use app\Support\Logging\SafeLogContext;
use support\exception\Handler;
use Throwable;
use Webman\Http\Request;
use Webman\Http\Response;

/**
 * 将领域异常映射为稳定 API 错误，隐藏内部堆栈和 SQL 信息。
 */
final class ApiExceptionHandler extends Handler
{
    /**
     * 记录异常类型和定位信息，同时避免输出可能含敏感绑定值的异常消息。
     */
    public function report(Throwable $exception): void
    {
        if ($exception instanceof BusinessException) {
            return;
        }

        $exceptionData = ['request_id' => RequestContext::requestId()]
            + SafeLogContext::exception($exception);

        // 异常消息可能包含SQL绑定值，只记录定位所需的安全元数据。
        Log::error('api.request.failed', $exceptionData);
    }

    /**
     * 将业务异常和未知异常转换为统一API响应。
     */
    public function render(Request $request, Throwable $exception): Response
    {
        if ($exception instanceof BusinessException) {
            return CorsMiddleware::withCorsHeaders(
                $request,
                ApiResponse::error(
                    $exception->businessCode(),
                    $exception->getMessage(),
                    $exception->httpStatus(),
                    $exception->data(),
                ),
            );
        }

        if (str_starts_with($request->path(), '/api/')) {
            return CorsMiddleware::withCorsHeaders(
                $request,
                ApiResponse::error('INTERNAL_ERROR', '服务器内部错误', 500),
            );
        }

        return CorsMiddleware::withCorsHeaders(
            $request,
            ApiResponse::error('INTERNAL_ERROR', '服务器内部错误', 500),
        );
    }
}

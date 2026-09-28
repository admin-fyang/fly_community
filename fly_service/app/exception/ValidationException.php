<?php

declare(strict_types=1);

namespace app\exception;

/**
 * HTTP 输入不符合契约。
 */
final class ValidationException extends BusinessException
{
    /**
     * 创建统一的请求参数校验异常。
     */
    public function __construct(string $message = '请求参数不正确')
    {
        parent::__construct('VALIDATION_ERROR', $message, 422);
    }
}

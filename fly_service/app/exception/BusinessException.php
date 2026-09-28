<?php

declare(strict_types=1);

namespace app\exception;

use RuntimeException;

/**
 * 可安全返回客户端的业务异常。
 */
class BusinessException extends RuntimeException
{
    /**
     * 创建包含稳定业务码和HTTP状态的安全异常。
     */
    public function __construct(
        private readonly string $businessCode,
        string $safeMessage,
        private readonly int $httpStatus,
        private readonly array $data = [],
    ) {
        parent::__construct($safeMessage);
    }

    /**
     * 返回客户端可依赖的稳定业务错误码。
     */
    public function businessCode(): string
    {
        return $this->businessCode;
    }

    /**
     * 返回该业务异常对应的HTTP状态码。
     */
    public function httpStatus(): int
    {
        return $this->httpStatus;
    }

    /**
     * 返回客户端处理冷却、限额等业务冲突所需的安全结构化数据。
     *
     * @return array<string,mixed>
     */
    public function data(): array
    {
        return $this->data;
    }
}

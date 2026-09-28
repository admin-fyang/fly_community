<?php

declare(strict_types=1);

namespace app\Modules\Im\Domain\Exception;

use RuntimeException;

/**
 * Centrifugo发布失败。
 *
 * 仅保存脱敏错误码和是否可重试，不携带API Key、URL或消息正文。
 */
final class CentrifugoPublishException extends RuntimeException
{
    /**
     * 创建可安全持久化的发布异常。
     */
    public function __construct(
        private readonly string $safeCode,
        private readonly bool $retryable,
    ) {
        parent::__construct($safeCode);
    }

    /**
     * 返回可写入Outbox的脱敏错误码。
     */
    public function safeCode(): string
    {
        return $this->safeCode;
    }

    /**
     * 判断失败是否允许自动重试。
     */
    public function retryable(): bool
    {
        return $this->retryable;
    }
}

<?php

declare(strict_types=1);

namespace app\Support\Logging;

use Throwable;

/** 日志只接收诊断摘要，未知字段和敏感字段默认拒绝。 */
final class SafeLogContext
{
    /** 先拒绝敏感键，再按类型验证白名单；不递归复制任意请求或响应。 */
    public static function summary(array $values): array
    {
        $safe = [];
        foreach ($values as $key => $value) {
            if (!is_string($key) || preg_match('/password|passwd|token|secret|authorization|cookie|phone|email|bank|wallet|content|body|upload|verification/i', $key)) {
                continue;
            }
            if (in_array($key, ['message_id', 'conversation_id', 'group_id', 'user_id', 'event_id', 'outbox_id'], true)) {
                if ((is_int($value) && $value > 0) || (is_string($value) && preg_match('/^[1-9][0-9]{0,19}$/D', $value))) {
                    $safe[$key] = $value;
                }
            } elseif (in_array($key, ['limit', 'count', 'attempted', 'published', 'retry', 'dead', 'duration_ms', 'http_status', 'request_size', 'response_size'], true)) {
                if ((is_int($value) || is_float($value)) && is_finite((float) $value) && $value >= 0) {
                    $safe[$key] = $value;
                }
            } elseif ($key === 'request_id' && is_string($value) && preg_match('/^[0-9A-HJKMNP-TV-Z]{26}$/D', $value)) {
                $safe[$key] = $value;
            }
        }
        return $safe;
    }

    /** 正文仅计字节数，绝不保留内容、嵌套数据或上传文件。 */
    public static function request(array $values): array
    {
        $safe = self::summary($values);
        if (is_string($values['body_text'] ?? null)) {
            $safe['body_length'] = strlen($values['body_text']);
        }
        return $safe;
    }

    /** 指纹只依赖异常类型和调用位置，消息及参数不会进入日志。 */
    public static function exception(Throwable $exception): array
    {
        return [
            'exception_class' => $exception::class,
            'error_fingerprint' => substr(hash('sha256', $exception::class . '|' . $exception->getFile() . '|' . $exception->getLine()), 0, 24),
            'file' => $exception->getFile(),
            'line' => $exception->getLine(),
            'trace' => array_map(
                static fn (array $frame): array => array_intersect_key($frame, array_flip(['file', 'line', 'class', 'function'])),
                array_slice($exception->getTrace(), 0, 32),
            ),
        ];
    }
}

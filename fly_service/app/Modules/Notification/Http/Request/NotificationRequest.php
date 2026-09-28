<?php

declare(strict_types=1);

namespace app\Modules\Notification\Http\Request;

use app\exception\BusinessException;
use support\Request;

/**
 * 系统通知请求解析器。
 */
final class NotificationRequest
{
    /**
     * 解析通知列表游标分页参数。
     *
     * @param Request $request HTTP请求对象
     * @return array{limit:int,before_notification_id:int|null}
     */
    public function parseList(Request $request): array
    {
        $limit = (int)($request->get('limit', 20));
        if ($limit < 1 || $limit > 100) {
            throw new BusinessException('VALIDATION_FAILED', 'limit必须在1到100之间', 422);
        }

        return [
            'limit' => $limit,
            'before_notification_id' => $this->nullablePositiveInt($request->get('before_notification_id')),
        ];
    }

    /**
     * 解析通知ID路径参数。
     */
    public function parseNotificationId(string $notificationId): int
    {
        $value = $this->nullablePositiveInt($notificationId);
        if ($value === null) {
            throw new BusinessException('VALIDATION_FAILED', '通知ID格式不正确', 422);
        }

        return $value;
    }

    /**
     * 解析通知处理动作。
     *
     * @return array{action:string,reason:string|null}
     */
    public function parseHandle(Request $request): array
    {
        $action = (string)$request->post('action', '');
        if (!in_array($action, ['accept', 'reject'], true)) {
            throw new BusinessException('VALIDATION_FAILED', '通知处理动作只能是accept或reject', 422);
        }

        $reason = $this->nullableText($request->post('reason'), 255, '拒绝原因最多255字符');
        /*if ($action === 'reject' && $reason === null) {
            throw new BusinessException('VALIDATION_FAILED', '拒绝原因不能为空', 422);
        }*/

        return ['action' => $action, 'reason' => $action === 'reject' ? $reason : null];
    }

    /**
     * 将可空正整数输入转为整数。
     */
    private function nullablePositiveInt(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_scalar($value) || !ctype_digit((string)$value)) {
            return null;
        }
        $integer = (int)$value;

        return $integer > 0 ? $integer : null;
    }

    /**
     * 解析可空短文本。
     */
    private function nullableText(mixed $value, int $maxLength, string $message): ?string
    {
        if ($value === null) {
            return null;
        }
        $text = trim((string)$value);
        if ($text === '') {
            return null;
        }
        if (mb_strlen($text) > $maxLength) {
            throw new BusinessException('VALIDATION_FAILED', $message, 422);
        }

        return $text;
    }
}

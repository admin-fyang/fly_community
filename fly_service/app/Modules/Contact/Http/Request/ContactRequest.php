<?php

declare(strict_types=1);

namespace app\Modules\Contact\Http\Request;

use app\exception\BusinessException;
use support\Request;

/**
 * 联系人接口请求解析器。
 */
final class ContactRequest
{
    /**
     * 解析联系人列表参数。
     *
     * @return array{cursor:int|null,limit:int}
     */
    public function list(Request $request): array
    {
        return [
            'cursor' => $this->nullablePositiveInt($request->get('cursor')),
            'limit' => $this->limit($request->get('limit', 50), 100),
        ];
    }

    /**
     * 解析用户搜索参数。
     *
     * @return array{keyword:string,limit:int,country_code:string|null}
     */
    public function search(Request $request): array
    {
        $keyword = trim((string)$request->get('keyword', ''));
        if ($keyword === '' || mb_strlen($keyword) > 2048) {
            throw new BusinessException('VALIDATION_ERROR', '搜索关键词不能为空且最多2048字符', 422);
        }

        return [
            'keyword' => $keyword,
            'limit' => $this->limit($request->get('limit', 20), 50),
            'country_code' => $request->get('country_code') === null ? null : (string)$request->get('country_code'),
        ];
    }

    /**
     * 解析路径用户ID。
     */
    public function userId(string $userId): int
    {
        $value = $this->nullablePositiveInt($userId);
        if ($value === null) {
            throw new BusinessException('VALIDATION_ERROR', '用户ID格式不正确', 422);
        }

        return $value;
    }

    /**
     * 解析好友申请参数。
     *
     * @return array{target_user_id:int,remark:string|null}
     */
    public function friendRequest(Request $request): array
    {
        $targetUserId = $this->nullablePositiveInt($request->post('target_user_id'));
        if ($targetUserId === null) {
            throw new BusinessException('VALIDATION_ERROR', 'target_user_id格式不正确', 422);
        }

        return [
            'target_user_id' => $targetUserId,
            'remark' => $this->nullableText($request->post('remark'), 100, '申请备注最多100字符'),
        ];
    }

    /**
     * 解析备注参数。
     *
     * @return array{remark:string|null}
     */
    public function remark(Request $request): array
    {
        return [
            'remark' => $this->nullableText($request->post('remark', ''), 64, '好友备注最多2048字符'),
        ];
    }

    /**
     * 解析联系人个人设置。
     *
     * @return array{is_pinned:bool|null,is_muted:bool|null}
     */
    public function settings(Request $request): array
    {
        return [
            'is_pinned' => $this->nullableBool($request->post('is_pinned')),
            'is_muted' => $this->nullableBool($request->post('is_muted')),
        ];
    }

    /**
     * 解析分页上限。
     */
    private function limit(mixed $value, int $max): int
    {
        if (!is_scalar($value) || !ctype_digit((string)$value)) {
            throw new BusinessException('VALIDATION_ERROR', 'limit格式不正确', 422);
        }
        $limit = (int)$value;
        if ($limit < 1 || $limit > $max) {
            throw new BusinessException('VALIDATION_ERROR', 'limit超出允许范围', 422);
        }

        return $limit;
    }

    /**
     * 将可空正整数转换为int。
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
        $text = trim((string)$value);
        if ($text === '') {
            return null;
        }
        if (mb_strlen($text) > $maxLength) {
            throw new BusinessException('VALIDATION_ERROR', $message, 422);
        }

        return $text;
    }

    /**
     * 解析可空布尔值。
     */
    private function nullableBool(mixed $value): ?bool
    {
        if ($value === null) {
            return null;
        }
        if (is_bool($value)) {
            return $value;
        }
        if ($value === 1 || $value === '1' || $value === 'true') {
            return true;
        }
        if ($value === 0 || $value === '0' || $value === 'false') {
            return false;
        }

        throw new BusinessException('VALIDATION_ERROR', '布尔参数格式不正确', 422);
    }
}

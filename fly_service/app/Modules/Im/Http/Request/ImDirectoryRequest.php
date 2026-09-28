<?php

declare(strict_types=1);

namespace app\Modules\Im\Http\Request;

use app\exception\BusinessException;
use support\Request;

/**
 * 通讯录目录同步请求解析器。
 *
 * 游标由服务端签发并原样回传，客户端不能拼装或修改其中的快照修订号。
 */
final class ImDirectoryRequest
{
    /** @return array{cursor:string|null,limit:int} */
    public function bootstrap(Request $request): array
    {
        $cursor = trim((string)$request->get('cursor', ''));
        if (strlen($cursor) > 512) {
            throw new BusinessException('VALIDATION_ERROR', '目录游标格式不正确', 422);
        }

        return [
            'cursor' => $cursor === '' ? null : $cursor,
            'limit' => $this->limit($request->get('limit', 200), 200),
        ];
    }

    /** @return list<array{user_id:int,profile_version:int}> */
    public function userBriefVersions(Request $request): array
    {
        $input = $request->post();
        if ($input === []) {
            $decoded = json_decode($request->rawBody(), true);
            $input = is_array($decoded) ? $decoded : [];
        }
        $items = $input['items'] ?? null;
        if (!is_array($items) || count($items) > 200) {
            throw new BusinessException('VALIDATION_ERROR', 'items必须为不超过200项的数组', 422);
        }

        $result = [];
        foreach ($items as $item) {
            if (!is_array($item)
                || !ctype_digit((string)($item['user_id'] ?? ''))
                || !ctype_digit((string)($item['profile_version'] ?? ''))
            ) {
                throw new BusinessException('VALIDATION_ERROR', '用户摘要版本格式不正确', 422);
            }
            $userId = (int)$item['user_id'];
            if ($userId < 1) {
                throw new BusinessException('VALIDATION_ERROR', 'user_id格式不正确', 422);
            }
            $result[$userId] = [
                'user_id' => $userId,
                'profile_version' => (int)$item['profile_version'],
            ];
        }

        return array_values($result);
    }

    /**
     * 校验目录分页大小处于允许范围。
     */
    private function limit(mixed $value, int $maximum): int
    {
        if (!is_scalar($value) || !ctype_digit((string)$value)) {
            throw new BusinessException('VALIDATION_ERROR', 'limit格式不正确', 422);
        }
        $limit = (int)$value;
        if ($limit < 1 || $limit > $maximum) {
            throw new BusinessException('VALIDATION_ERROR', 'limit超出允许范围', 422);
        }

        return $limit;
    }
}

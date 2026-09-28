<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Request;

use app\exception\BusinessException;
use app\exception\ValidationException;
use Webman\Http\Request;

/** 设备管理仅接受分页输入，身份始终来自认证上下文。 */
final class DeviceSessionRequest
{
    /** 严格校验查询字符串，数组型或空游标统一返回契约错误。 */
    public function listing(Request $request): array
    {
        $limit = $request->get('limit', '20');
        if ((!is_int($limit) && !is_string($limit)) || preg_match('/^[1-9][0-9]{0,2}$/D', (string)$limit) !== 1 || (int)$limit > 100) {
            throw new ValidationException('limit 必须为 1 至 100 的整数');
        }
        $cursor = $request->get('cursor');
        if ($cursor !== null && (!is_string($cursor) || strlen($cursor) > 160 || $cursor === '')) {
            throw new BusinessException('AUTH_SESSION_CURSOR_INVALID', '设备列表已失效，请刷新后重试', 400);
        }
        return ['limit' => (int)$limit, 'cursor' => $cursor];
    }

    /** 损坏的目标标识和不存在的标识使用同一 404，不透露其他账号的会话。 */
    public function sessionId(string $value): string
    {
        if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iD', $value) !== 1) {
            throw new BusinessException('AUTH_SESSION_NOT_FOUND', '登录会话不存在', 404);
        }
        return strtolower($value);
    }
}

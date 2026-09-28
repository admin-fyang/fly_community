<?php

declare(strict_types=1);

namespace app\Modules\User\Http\Request;

use app\exception\BusinessException;
use Webman\Http\Request;

/**
 * 用户资料修改请求白名单与格式校验。
 */
final class UserProfileRequest
{
    /**
     * 校验 PATCH 字段并保留“缺失”与显式 null 的区别。
     *
     * @return array<string, mixed>
     */
    public function update(Request $request): array
    {
        $input = $request->post();
        if (!is_array($input) || !isset($input['profile_version']) || !is_int($input['profile_version'])) {
            throw new BusinessException('VALIDATION_ERROR', 'profile_version 必须为整数', 422);
        }

        $data = ['profile_version' => $input['profile_version']];
        foreach (['first_name', 'last_name', 'username', 'bio', 'birthday', 'region_code'] as $field) {
            if (!array_key_exists($field, $input)) {
                continue;
            }
            if ($input[$field] !== null && !is_string($input[$field])) {
                throw new BusinessException('VALIDATION_ERROR', "{$field} 必须为字符串或 null", 422);
            }
            $data[$field] = $input[$field] === null ? null : trim($input[$field]);
        }

        foreach (['sex', 'birthday_visibility', 'phone_visibility', 'last_seen_visibility'] as $field) {
            if (array_key_exists($field, $input)) {
                if (!is_int($input[$field])) {
                    throw new BusinessException('VALIDATION_ERROR', "{$field} 必须为整数", 422);
                }
                $data[$field] = $input[$field];
            }
        }

        return $data;
    }

    /**
     * 校验头像资源绑定请求。
     */
    public function avatarResourceId(Request $request): string
    {
        $resourceId = $request->post('resource_id');
        if (!is_string($resourceId) || preg_match('/^[0-9a-f-]{36}$/i', $resourceId) !== 1) {
            throw new BusinessException('VALIDATION_ERROR', 'resource_id 格式不正确', 422);
        }
        return strtolower($resourceId);
    }
}

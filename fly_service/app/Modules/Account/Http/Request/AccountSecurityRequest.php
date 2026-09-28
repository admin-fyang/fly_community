<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Request;

use app\exception\BusinessException;
use app\Modules\Account\Domain\Enum\AuthChannel;
use Webman\Http\Request;

/**
 * 密码与账号注销接口输入白名单校验器。
 */
final class AccountSecurityRequest
{
    /** @return array{channel:AuthChannel,account:string,country_code:?string,verification_request_id:string,code:string,new_password:string} */
    public function resetPassword(Request $request): array
    {
        $channel = AuthChannel::tryFrom($this->string($request->post('channel'), 'channel', 16));
        if ($channel === null) throw new BusinessException('VALIDATION_ERROR', 'channel 不受支持', 422);
        $code = $this->string($request->post('code'), 'code', 6);
        if (preg_match('/^[0-9]{6}$/', $code) !== 1) throw new BusinessException('VALIDATION_ERROR', 'code 必须为6位数字', 422);
        return [
            'channel' => $channel,
            'account' => $this->string($request->post('account'), 'account', 254),
            'country_code' => $this->optional($request->post('country_code'), 4),
            'verification_request_id' => $this->uuid($request->post('verification_request_id')),
            'code' => $code,
            'new_password' => $this->string($request->post('new_password'), 'new_password', 128, false),
        ];
    }

    /** @return array{current_password:string,new_password:string} */
    public function changePassword(Request $request): array
    {
        return [
            'current_password' => $this->string($request->post('current_password'), 'current_password', 128, false),
            'new_password' => $this->string($request->post('new_password'), 'new_password', 128, false),
        ];
    }

    /** 读取注销申请使用的当前密码。 */
    public function currentPassword(Request $request): string
    {
        return $this->string($request->post('current_password'), 'current_password', 128, false);
    }

    /** 校验注销申请业务ID。 */
    public function deletionId(string $value): string
    {
        if (preg_match('/^del_[0-9a-f]{32}$/', $value) !== 1) throw new BusinessException('VALIDATION_ERROR', '注销申请ID格式不正确', 422);
        return $value;
    }

    /** 校验验证码请求UUID。 */
    private function uuid(mixed $value): string
    {
        $value = $this->string($value, 'verification_request_id', 36);
        if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $value) !== 1) throw new BusinessException('VALIDATION_ERROR', 'verification_request_id 必须为UUID v4', 422);
        return strtolower($value);
    }

    /** 校验必填字符串，并允许密码字段保持原始空白。 */
    private function string(mixed $value, string $field, int $max, bool $trim = true): string
    {
        if (!is_string($value) || $value === '' || mb_strlen($value) > $max) throw new BusinessException('VALIDATION_ERROR', $field . ' 格式不正确', 422);
        return $trim ? trim($value) : $value;
    }

    /** 校验可空国家码字符串。 */
    private function optional(mixed $value, int $max): ?string
    {
        return $value === null || $value === '' ? null : $this->string($value, 'country_code', $max);
    }
}

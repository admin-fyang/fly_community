<?php

declare(strict_types=1);

namespace app\Modules\Account\Http\Request;

use app\Modules\Account\Application\DTO\LoginWithPasswordInput;
use app\Modules\Account\Application\DTO\RegisterUserInput;
use app\Modules\Account\Application\DTO\RegistrationVerificationInput;
use app\Modules\Account\Application\DTO\SendVerificationCodeInput;
use app\Modules\Account\Domain\DTO\DeviceData;
use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\Enum\VerificationScene;
use app\exception\ValidationException;
use Webman\Http\Request;

/**
 * 登录注册 HTTP 输入白名单与基础格式校验。
 */
final class AuthRequestValidator
{
    /**
     * 校验发送验证码请求并转换为用例输入。
     */
    public function verificationCode(Request $request): SendVerificationCodeInput
    {
        $channel = AuthChannel::tryFrom($this->requiredString($request->post('channel'), 'channel'));
        $purpose = $request->post('purpose');
        $scene = $purpose === 'reset_password'
            ? match ($channel) {
                AuthChannel::Phone => VerificationScene::ResetPasswordPhone,
                AuthChannel::Email => VerificationScene::ResetPasswordEmail,
                default => null,
            }
            : VerificationScene::tryFrom($this->requiredString($request->post('scene'), 'scene'));
        if ($scene === null || $channel === null) {
            throw new ValidationException('scene、purpose 或 channel 不受支持');
        }

        return new SendVerificationCodeInput(
            $scene,
            $channel,
            $this->boundedString($request->post('target'), 'target', 1, 254),
            $this->optionalCountryCode($request->post('country_code')),
            $request->getRemoteIp(),
        );
    }

    /**
     * 校验注册请求并转换为用例输入。
     */
    public function registration(Request $request): RegisterUserInput
    {
        return new RegisterUserInput(
            $this->boundedString($request->post('username'), 'username', 5, 33),
            $this->boundedString($request->post('nickname'), 'nickname', 1, 64),
            $this->boundedString($request->post('password'), 'password', 1, 128, false),
            $this->optionalString($request->post('invite_code'), 64),
            $this->registrationVerification(
                $request->post('phone_verification'),
                AuthChannel::Phone,
                'phone_verification',
            ),
            $this->registrationVerification(
                $request->post('email_verification'),
                AuthChannel::Email,
                'email_verification',
            ),
            $this->device($request->post('device')),
            $request->getRemoteIp(),
            (string) $request->header('user-agent', ''),
        );
    }

    /**
     * 校验注册时可选的手机号或邮箱验证码对象。
     */
    private function registrationVerification(
        mixed $value,
        AuthChannel $channel,
        string $field,
    ): ?RegistrationVerificationInput {
        if ($value === null) {
            return null;
        }
        if (!is_array($value)) {
            throw new ValidationException($field . ' 必须为对象');
        }

        $accountField = $channel === AuthChannel::Phone ? 'phone' : 'email';
        $code = $this->boundedString($value['code'] ?? null, $field . '.code', 6, 6);
        if (preg_match('/^[0-9]{6}$/', $code) !== 1) {
            throw new ValidationException($field . '.code 必须为6位数字');
        }

        return new RegistrationVerificationInput(
            $channel,
            $this->boundedString($value[$accountField] ?? null, $field . '.' . $accountField, 1, 254),
            $channel === AuthChannel::Phone
                ? $this->optionalCountryCode($value['country_code'] ?? null)
                : null,
            $this->uuid($value['verification_request_id'] ?? null, $field . '.verification_request_id'),
            $code,
        );
    }

    /**
     * 校验密码登录请求并转换为用例输入。
     */
    public function passwordLogin(Request $request): LoginWithPasswordInput
    {
        return new LoginWithPasswordInput(
            $this->boundedString($request->post('account'), 'account', 1, 254),
            $this->optionalCountryCode($request->post('country_code')),
            $this->boundedString($request->post('password'), 'password', 1, 128, false),
            $this->device($request->post('device')),
            $request->getRemoteIp(),
            (string) $request->header('user-agent', ''),
        );
    }

    /**
     * 校验设备对象并裁剪为允许进入业务层的字段。
     */
    private function device(mixed $value): DeviceData
    {
        if (!is_array($value)) {
            throw new ValidationException('device 必须为对象');
        }

        $platform = $this->requiredString($value['platform'] ?? null, 'device.platform');
        if (!in_array($platform, ['android', 'ios', 'web', 'windows', 'macos', 'linux'], true)) {
            throw new ValidationException('device.platform 不受支持');
        }

        return new DeviceData(
            $this->uuid($value['device_id'] ?? null, 'device.device_id'),
            $platform,
            $this->boundedString($value['device_name'] ?? null, 'device.device_name', 1, 128),
            $this->optionalString($value['app_version'] ?? null, 32),
        );
    }

    /**
     * 校验字段是否为标准UUID v4。
     */
    private function uuid(mixed $value, string $field): string
    {
        $uuid = $this->requiredString($value, $field);
        if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $uuid) !== 1) {
            throw new ValidationException($field . ' 必须为 UUID v4');
        }

        return strtolower($uuid);
    }

    /**
     * 校验可选的电话国家码，允许 +86、86 和历史兼容的 CN。
     */
    private function optionalCountryCode(mixed $value): ?string
    {
        $countryCode = $this->optionalString($value, 4);
        if ($countryCode === null) {
            return null;
        }

        if (preg_match('/^[A-Za-z]{2}$/', $countryCode) === 1) {
            return strtoupper($countryCode);
        }

        if (preg_match('/^\+?[1-9][0-9]{0,2}$/', $countryCode) === 1) {
            return str_starts_with($countryCode, '+') ? $countryCode : '+' . $countryCode;
        }

        throw new ValidationException('country_code 必须为电话国家码，例如 +86');
    }

    /**
     * 读取可空字符串并执行最大长度限制。
     */
    private function optionalString(mixed $value, int $maxLength): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_string($value) || mb_strlen($value) > $maxLength) {
            throw new ValidationException('可选字符串字段格式不正确');
        }

        return trim($value);
    }

    /**
     * 读取必填字符串，缺失或类型错误时抛出校验异常。
     */
    private function requiredString(mixed $value, string $field): string
    {
        if (!is_string($value) || $value === '') {
            throw new ValidationException($field . ' 为必填字符串');
        }

        return $value;
    }

    /**
     * 校验字符串是否处于指定字符长度范围。
     */
    private function boundedString(
        mixed $value,
        string $field,
        int $minLength,
        int $maxLength,
        bool $trim = true,
    ): string {
        $string = $this->requiredString($value, $field);
        $string = $trim ? trim($string) : $string;
        $length = mb_strlen($string);
        if ($length < $minLength || $length > $maxLength) {
            throw new ValidationException("{$field} 长度必须在 {$minLength} 至 {$maxLength} 之间");
        }

        return $string;
    }
}

<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\Service;

use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\ValueObject\NormalizedContact;
use app\exception\ValidationException;
use libphonenumber\NumberParseException;
use libphonenumber\PhoneNumberFormat;
use libphonenumber\PhoneNumberUtil;

/**
 * 将手机号和邮箱转换为唯一、稳定的登录规范值。
 */
final class ContactNormalizer
{
    /**
     * 注入国际手机号解析器。
     */
    public function __construct(private readonly PhoneNumberUtil $phones)
    {
    }

    /**
     * 按渠道规范化原始联系方式并生成脱敏展示值。
     */
    public function normalize(AuthChannel $channel, string $rawValue, ?string $countryCode): NormalizedContact
    {
        return match ($channel) {
            AuthChannel::Phone => $this->normalizePhone($rawValue, $countryCode),
            AuthChannel::Email => $this->normalizeEmail($rawValue),
        };
    }

    /**
     * 将手机号解析并转换为唯一的E.164格式。
     */
    private function normalizePhone(string $rawValue, ?string $countryCode): NormalizedContact
    {
        $value = trim($rawValue);
        $region = null;
        if (!str_starts_with($value, '+')) {
            $region = $this->resolveRegionCode($countryCode);
            if ($region === null) {
                throw new ValidationException('非 E.164 手机号必须提供 country_code');
            }
        }

        try {
            $number = $this->phones->parse($value, $region);
        } catch (NumberParseException) {
            throw new ValidationException('手机号格式不正确');
        }

        if (!$this->phones->isValidNumber($number)) {
            throw new ValidationException('手机号格式不正确');
        }

        $normalized = $this->phones->format($number, PhoneNumberFormat::E164);
        $national = (string) $number->getNationalNumber();
        $maskedNational = strlen($national) > 7
            ? substr($national, 0, 3) . str_repeat('*', strlen($national) - 7) . substr($national, -4)
            : str_repeat('*', max(0, strlen($national) - 2)) . substr($national, -2);
        $masked = '+' . $number->getCountryCode() . ' ' . $maskedNational;

        return new NormalizedContact(AuthChannel::Phone, $normalized, $masked);
    }

    /**
     * 将电话国家码转换为手机号解析器需要的地区码。
     */
    private function resolveRegionCode(?string $countryCode): ?string
    {
        $code = strtoupper(trim((string) $countryCode));
        if (preg_match('/^[A-Z]{2}$/', $code) === 1) {
            return $code;
        }

        if (preg_match('/^\+?[1-9][0-9]{0,2}$/', $code) !== 1) {
            return null;
        }

        $callingCode = (int) ltrim($code, '+');
        $region = $this->phones->getRegionCodeForCountryCode($callingCode);

        return $region === 'ZZ' ? null : $region;
    }

    /**
     * 将邮箱域名转换为ASCII并执行大小写归一化。
     */
    private function normalizeEmail(string $rawValue): NormalizedContact
    {
        $value = trim($rawValue);
        if (mb_strlen($value) > 254 || substr_count($value, '@') !== 1) {
            throw new ValidationException('邮箱格式不正确');
        }

        [$local, $domain] = explode('@', $value, 2);
        $asciiDomain = idn_to_ascii($domain, IDNA_DEFAULT, INTL_IDNA_VARIANT_UTS46);
        if ($asciiDomain === false) {
            throw new ValidationException('邮箱域名格式不正确');
        }

        $normalized = mb_strtolower($local) . '@' . strtolower($asciiDomain);
        if (filter_var($normalized, FILTER_VALIDATE_EMAIL) === false) {
            throw new ValidationException('邮箱格式不正确');
        }
        $visible = mb_substr($local, 0, 1);
        $masked = $visible . str_repeat('*', max(3, min(8, mb_strlen($local) - 1))) . '@' . strtolower($asciiDomain);

        return new NormalizedContact(AuthChannel::Email, $normalized, $masked);
    }
}

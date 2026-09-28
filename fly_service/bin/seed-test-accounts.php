#!/usr/bin/env php
<?php

declare(strict_types=1);

use app\Infrastructure\Persistence\IlluminateTransactionManager;
use app\Modules\Account\Application\DTO\RegisterUserInput;
use app\Modules\Account\Application\Service\ContactNormalizer;
use app\Modules\Account\Application\Service\ContactProtector;
use app\Modules\Account\Application\Service\PasswordHasher;
use app\Modules\Account\Application\Service\VerificationCodeHasher;
use app\Modules\Account\Application\UseCase\RegisterUser;
use app\Modules\Account\Domain\DTO\DeviceData;
use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\Enum\VerificationScene;
use app\Modules\Account\Domain\Repository\VerificationCodeRepository;
use app\Modules\Account\Infrastructure\Persistence\Eloquent\Repository\EloquentAuthRepository;
use app\Modules\Account\Infrastructure\Security\EdDsaJwtAccessTokenIssuer;
use app\Modules\Account\Infrastructure\Security\RefreshTokenFactory;
use app\Support\Id\IdGenerator;
use app\exception\BusinessException;
use libphonenumber\PhoneNumberUtil;

chdir(dirname(__DIR__));

require_once __DIR__ . '/../vendor/autoload.php';

$worker = null;
require_once __DIR__ . '/../support/bootstrap.php';

$options = getopt('', [
    'start::',
    'count::',
    'country-code::',
    'password::',
    'platform::',
    'device-name::',
    'app-version::',
    'ip::',
    'help',
]);

if (isset($options['help'])) {
    fwrite(STDOUT, <<<'TEXT'
Usage:
  php bin/seed-test-accounts.php [options]

Options:
  --start=13800000001       起始本地手机号，默认 13800000001
  --count=9                 创建数量，默认 9
  --country-code=+86        电话国家码，支持 +86、86、853、886，默认 +86
  --password=TestPass123    统一测试密码，默认 TestPass123
  --platform=android        设备平台，默认 android
  --device-name=Seed Phone  设备名称，默认 Seed Phone
  --app-version=1.0.0       App 版本，默认 1.0.0
  --ip=127.0.0.1            注册 IP，默认 127.0.0.1

TEXT);
    exit(0);
}

$start = (int) ($options['start'] ?? 13_800_000_001);
$count = (int) ($options['count'] ?? 9);
$countryCode = (string) ($options['country-code'] ?? '+86');
$password = (string) ($options['password'] ?? 'TestPass123');
$platform = (string) ($options['platform'] ?? 'android');
$deviceName = (string) ($options['device-name'] ?? 'Seed Phone');
$appVersion = (string) ($options['app-version'] ?? '1.0.0');
$ip = (string) ($options['ip'] ?? '127.0.0.1');

if ($start <= 0 || $count <= 0) {
    fwrite(STDERR, "start 和 count 必须为正整数\n");
    exit(1);
}

$requiredConfig = [
    'auth.contact_lookup_key' => config('auth.contact_lookup_key'),
    'auth.contact_encryption_key' => config('auth.contact_encryption_key'),
    'auth.refresh_token_key' => config('auth.refresh_token_key'),
    'auth.verification_code_key' => config('auth.verification_code_key'),
    'auth.jwt.private_key' => config('auth.jwt.private_key'),
];

foreach ($requiredConfig as $name => $value) {
    if (!is_string($value) || $value === '') {
        fwrite(STDERR, "{$name} 未配置，请先运行 php bin/generate-auth-keys.php 并写入 .env\n");
        exit(1);
    }
}

$ids = new IdGenerator();
$verificationCodes = new class implements VerificationCodeRepository {
    /** 合成账号脚本不发送验证码，预占操作为空。 */
    public function reserve(
        string $requestId,
        VerificationScene $scene,
        string $targetHash,
        string $codeHash,
        string $ipHash,
        int $ttlSeconds,
        int $resendSeconds,
    ): void {
    }

    /** 合成账号脚本不激活外部验证码。 */
    public function activate(string $requestId): void
    {
    }

    /** 合成账号脚本没有外部验证码状态需要撤销。 */
    public function cancel(string $requestId, VerificationScene $scene, string $targetHash): void
    {
    }

    /** 合成账号脚本直接跳过验证码消费，仅用于专用测试数据。 */
    public function consume(
        string $requestId,
        VerificationScene $scene,
        string $targetHash,
        string $codeHash,
        int $maxAttempts,
    ): void {
    }
};

$useCase = new RegisterUser(
    new ContactNormalizer(PhoneNumberUtil::getInstance()),
    new ContactProtector(
        config('auth.contact_lookup_key'),
        config('auth.contact_encryption_key'),
    ),
    new VerificationCodeHasher(config('auth.verification_code_key')),
    $verificationCodes,
    new PasswordHasher(),
    new EloquentAuthRepository(
        $ids,
        new RefreshTokenFactory(
            $ids,
            config('auth.refresh_token_key'),
            (int) config('auth.refresh_ttl_seconds'),
        ),
    ),
    new IlluminateTransactionManager(),
    new EdDsaJwtAccessTokenIssuer(
        $ids,
        config('auth.jwt.private_key'),
        config('auth.jwt.key_id'),
        config('auth.jwt.issuer'),
        config('auth.jwt.audience'),
        (int) config('auth.jwt.ttl_seconds'),
    ),
    $ids,
    (int) config('auth.verification.max_attempts'),
);

$created = 0;
$skipped = 0;
$failed = 0;

for ($offset = 0; $offset < $count; $offset++) {
    $phone = (string) ($start + $offset);
    $deviceId = $ids->uuidV4();

    try {
        $result = $useCase->execute(new RegisterUserInput(
            AuthChannel::Phone,
            $phone,
            $countryCode,
            $ids->uuidV4(),
            '123456',
            // $password,
            $phone,
            null,
            new DeviceData($deviceId, $platform, $deviceName, $appVersion),
            $ip,
            'seed-test-accounts.php',
        ));

        $created++;
        fwrite(STDOUT, sprintf(
            "CREATED phone=%s user_id=%s public_id=%s\n",
            $phone,
            $result->user['id'] ?? '',
            $result->user['public_id'] ?? '',
        ));
    } catch (BusinessException $exception) {
        if ($exception->businessCode() === 'CONTACT_ALREADY_REGISTERED') {
            $skipped++;
            fwrite(STDOUT, sprintf("SKIPPED phone=%s reason=already_registered\n", $phone));
            continue;
        }

        $failed++;
        fwrite(STDERR, sprintf(
            "FAILED phone=%s code=%s message=%s\n",
            $phone,
            $exception->businessCode(),
            $exception->getMessage(),
        ));
    } catch (Throwable $exception) {
        $failed++;
        fwrite(STDERR, sprintf(
            "FAILED phone=%s exception=%s message=%s\n",
            $phone,
            $exception::class,
            $exception->getMessage(),
        ));
    }
}

fwrite(STDOUT, sprintf(
    "DONE created=%d skipped=%d failed=%d\n",
    $created,
    $skipped,
    $failed,
));

exit($failed > 0 ? 1 : 0);

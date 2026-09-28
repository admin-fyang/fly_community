<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\UseCase;

use app\Modules\Account\Application\DTO\RegisterUserInput;
use app\Modules\Account\Application\DTO\RegistrationVerificationInput;
use app\Modules\Account\Application\Service\ContactNormalizer;
use app\Modules\Account\Application\Service\ContactProtector;
use app\Modules\Account\Application\Service\PasswordHasher;
use app\Modules\Account\Application\Service\UsernamePolicy;
use app\Modules\Account\Application\Service\VerificationCodeHasher;
use app\Modules\Account\Domain\DTO\AuthSessionData;
use app\Modules\Account\Domain\DTO\VerificationCodeClaim;
use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\Enum\VerificationScene;
use app\Modules\Account\Domain\Exception\GeneratedIdentityCollisionException;
use app\Modules\Account\Domain\Repository\AuthRepository;
use app\Modules\Account\Domain\Repository\VerificationCodeRepository;
use app\Modules\Account\Domain\Service\AccessTokenIssuer;
use app\exception\BusinessException;
use app\Support\Id\IdGenerator;
use app\Support\Transaction\TransactionManager;
use app\Modules\System\Application\SystemConfigService;
use RuntimeException;

/**
 * 用户名密码注册完整事务。
 */
final class RegisterUser
{
    /**
     * 注入注册流程所需的验证码、密码、事务和令牌能力。
     */
    public function __construct(
        private readonly ContactNormalizer $normalizer,
        private readonly ContactProtector $protector,
        private readonly VerificationCodeHasher $codeHasher,
        private readonly VerificationCodeRepository $verificationCodes,
        private readonly PasswordHasher $passwords,
        private readonly UsernamePolicy $usernames,
        private readonly AuthRepository $auth,
        private readonly TransactionManager $transactions,
        private readonly AccessTokenIssuer $accessTokens,
        private readonly IdGenerator $ids,
        private readonly int $maxVerificationAttempts,
        private readonly ?SystemConfigService $systemConfig = null,
    ) {
    }

    /**
     * 消费验证码并在单个事务中创建用户、联系方式、设备和会话。
     */
    public function execute(RegisterUserInput $input): AuthSessionData
    {
        $policy = $this->systemConfig?->registrationPolicy() ?? [
            'open_register' => true,
            'phone_register_verification' => false,
            'email_register_verification' => false,
            'invite_register' => false,
        ];
        if (!$policy['open_register']) {
            throw new BusinessException('REGISTER_DISABLED', '注册功能已关闭', 403);
        }

        $username = $this->usernames->normalize($input->username);
        if ($this->auth->usernameExists($username)) {
            throw new BusinessException('USERNAME_ALREADY_USED', '用户名已被使用', 409);
        }
        $nickname = $this->validateNickname($input->nickname);

        $this->passwords->assertStrong($input->password);

        $inviterUsername = $input->inviteCode === null ? null : strtolower(ltrim(trim($input->inviteCode), '@'));
        $inviterUsername = $inviterUsername === '' ? null : $inviterUsername;
        if ($policy['invite_register'] && $inviterUsername === null) {
            throw new BusinessException('INVITE_CODE_REQUIRED', '注册必须填写有效邀请码', 422);
        }
        if (!$policy['invite_register']) {
            $inviterUsername = null;
        }

        [$contacts, $claims] = $this->prepareVerifications($input, $policy);
        foreach ($contacts as $contact) {
            if ($this->auth->contactExists($contact)) {
                throw new BusinessException('CONTACT_ALREADY_REGISTERED', '该联系方式已注册', 409);
            }
        }
        if ($claims !== []) {
            $this->verificationCodes->consumeAll($claims, $this->maxVerificationAttempts);
        }
        $passwordHash = $this->passwords->hash($input->password);

        for ($attempt = 0; $attempt < 5; $attempt++) {
            try {
                $now = time();
                $registered = $this->transactions->run(function () use ($username, $nickname, $contacts, $passwordHash, $inviterUsername, $input, $now) {
                    $registered = $this->auth->createRegisteredUser(
                    $username,
                    $nickname,
                    $contacts,
                    $passwordHash,
                    $this->ids->publicId(),
                    $inviterUsername,
                    $input->device,
                    $input->clientIp,
                    $input->userAgent,
                    $now,
                    );
                    return $registered;
                });

                $accessToken = $this->accessTokens->issue(
                    $registered->user->userId,
                    $registered->session->sessionId,
                    $input->device->deviceId,
                    $now,
                );

                return new AuthSessionData(
                    $accessToken,
                    $this->accessTokens->ttlSeconds(),
                    $registered->session->refreshToken,
                    $registered->session->refreshExpiresIn,
                    $registered->session->sessionId,
                    $registered->user->apiSummary(),
                );
            } catch (GeneratedIdentityCollisionException) {
                continue;
            }
        }

        throw new RuntimeException('生成用户公开标识连续冲突');
    }

    /**
     * 校验注册昵称并返回去除首尾空白后的值。
     */
    private function validateNickname(string $value): string
    {
        $nickname = trim($value);
        if ($nickname === '' || mb_strlen($nickname) > 64) {
            throw new BusinessException('NICKNAME_INVALID', '昵称长度必须为1至64字符', 422);
        }

        return $nickname;
    }

    /**
     * 按两个独立开关构造联系方式和验证码声明。
     *
     * 开关关闭时拒绝对应输入，避免客户端误以为未验证的联系方式已经绑定。
     *
     * @param array<string,bool> $policy
     * @return array{0:list<\app\Modules\Account\Domain\ValueObject\ProtectedContact>,1:list<VerificationCodeClaim>}
     */
    private function prepareVerifications(RegisterUserInput $input, array $policy): array
    {
        $contacts = [];
        $claims = [];
        foreach ([
            [$policy['phone_register_verification'], $input->phoneVerification, AuthChannel::Phone],
            [$policy['email_register_verification'], $input->emailVerification, AuthChannel::Email],
        ] as [$required, $verification, $channel]) {
            if (!$required && $verification !== null) {
                throw new BusinessException('REGISTER_VERIFICATION_DISABLED', '当前联系方式的注册验证已关闭', 422);
            }
            if ($required && !$verification instanceof RegistrationVerificationInput) {
                throw new BusinessException('REGISTER_VERIFICATION_REQUIRED', '注册必须完成已开启的联系方式验证', 422);
            }
            if (!$verification instanceof RegistrationVerificationInput) {
                continue;
            }
            if ($verification->channel !== $channel) {
                throw new BusinessException('REGISTER_VERIFICATION_INVALID', '注册验证渠道与字段不匹配', 422);
            }

            $contact = $this->normalizer->normalize($channel, $verification->account, $verification->countryCode);
            $protected = $this->protector->protect($contact);
            $scene = $channel === AuthChannel::Phone
                ? VerificationScene::RegisterPhone
                : VerificationScene::RegisterEmail;
            $contacts[] = $protected;
            $claims[] = new VerificationCodeClaim(
                $verification->verificationRequestId,
                $scene,
                $this->protector->targetHash($contact),
                $this->codeHasher->hash($verification->verificationRequestId, $verification->code),
            );
        }

        return [$contacts, $claims];
    }
}

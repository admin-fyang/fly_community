<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\UseCase;

use app\Modules\Account\Application\DTO\SendVerificationCodeInput;
use app\Modules\Account\Application\Service\ContactNormalizer;
use app\Modules\Account\Application\Service\ContactProtector;
use app\Modules\Account\Application\Service\VerificationCodeGenerator;
use app\Modules\Account\Application\Service\VerificationCodeHasher;
use app\Modules\Account\Domain\Repository\AuthRepository;
use app\Modules\Account\Domain\Repository\VerificationCodeRepository;
use app\Modules\Account\Domain\Enum\AuthChannel;
use app\exception\BusinessException;
use app\Modules\Account\Domain\Service\VerificationCodeSender;
use app\exception\ValidationException;
use app\Support\Id\IdGenerator;
use app\Modules\System\Application\SystemConfigService;
use Throwable;

/**
 * 发送注册验证码。
 *
 * Redis先预留发送资格，供应商成功后再激活；供应商失败会释放当前请求。
 */
final class SendVerificationCode
{
    /**
     * 注入验证码生成、发送、限流及联系方式唯一性检查能力。
     */
    public function __construct(
        private readonly ContactNormalizer $normalizer,
        private readonly ContactProtector $protector,
        private readonly VerificationCodeGenerator $codes,
        private readonly VerificationCodeHasher $codeHasher,
        private readonly VerificationCodeRepository $verificationCodes,
        private readonly VerificationCodeSender $sender,
        private readonly AuthRepository $auth,
        private readonly IdGenerator $ids,
        private readonly int $ttlSeconds,
        private readonly int $resendSeconds,
        private readonly bool $exposeCode,
        private readonly ?SystemConfigService $systemConfig = null,
    ) {
    }

    /**
     * @return array<string, int|string>
     */
    public function execute(SendVerificationCodeInput $input): array
    {
        if ($input->scene->channel() !== $input->channel) {
            throw new ValidationException('scene 与 channel 不匹配');
        }

        if ($input->scene->isRegistration() && $this->systemConfig !== null) {
            $policy = $this->systemConfig->registrationPolicy();
            if (!$policy['open_register']) {
                throw new BusinessException('REGISTER_DISABLED', '注册功能已关闭', 403);
            }
            $verificationEnabled = $input->channel === AuthChannel::Phone
                ? $policy['phone_register_verification']
                : $policy['email_register_verification'];
            if (!$verificationEnabled) {
                throw new BusinessException('REGISTER_VERIFICATION_DISABLED', '当前联系方式的注册验证已关闭', 403);
            }
        }

        $contact = $this->normalizer->normalize($input->channel, $input->target, $input->countryCode);
        $protected = $this->protector->protect($contact);
        if ($input->scene->isRegistration() && $this->auth->contactExists($protected)) {
            throw new BusinessException(
                'CONTACT_ALREADY_REGISTERED',
                '该联系方式已注册',
                409,
            );
        }

        $requestId = $this->ids->uuidV4();
        $code = $this->codes->generate();
        $targetHash = $this->protector->targetHash($contact);
        $this->verificationCodes->reserve(
            $requestId,
            $input->scene,
            $targetHash,
            $this->codeHasher->hash($requestId, $code),
            $this->protector->opaqueHash($input->clientIp),
            $this->ttlSeconds,
            $this->resendSeconds,
        );

        try {
            $this->sender->send($contact, $code);
            $this->verificationCodes->activate($requestId);
        } catch (Throwable $exception) {
            $this->verificationCodes->cancel($requestId, $input->scene, $targetHash);
            throw $exception;
        }

        $result = [
            'verification_request_id' => $requestId,
            'expires_in' => $this->ttlSeconds,
            'resend_in' => $this->resendSeconds,
            'target_masked' => $contact->masked,
        ];

        if ($this->exposeCode) {
            $result['verification_code'] = $code;
        }

        return $result;
    }
}

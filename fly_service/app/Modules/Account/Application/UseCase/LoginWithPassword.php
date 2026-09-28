<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\UseCase;

use app\Modules\Account\Application\DTO\LoginWithPasswordInput;
use app\Modules\Account\Application\Service\ContactNormalizer;
use app\Modules\Account\Application\Service\ContactProtector;
use app\Modules\Account\Application\Service\PasswordHasher;
use app\Modules\Account\Domain\DTO\AuthSessionData;
use app\Modules\Account\Domain\DTO\AuthenticatedUser;
use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\Repository\AuthRepository;
use app\Modules\Account\Domain\Repository\LoginRateLimiter;
use app\Modules\Account\Domain\Service\AccessTokenIssuer;
use app\exception\BusinessException;
use app\exception\ValidationException;
use app\enum\UserStatus;
use app\Support\Transaction\TransactionManager;

/**
 * 手机号、邮箱或用户名密码登录。
 */
final class LoginWithPassword
{
    /**
     * 注入登录所需的身份解析、仓储、限流、事务和令牌能力。
     */
    public function __construct(
        private readonly ContactNormalizer $normalizer,
        private readonly ContactProtector $protector,
        private readonly PasswordHasher $passwords,
        private readonly AuthRepository $auth,
        private readonly LoginRateLimiter $rateLimiter,
        private readonly TransactionManager $transactions,
        private readonly AccessTokenIssuer $accessTokens,
    ) {
    }

    /**
     * 校验登录身份和密码，创建新会话并签发令牌。
     */
    public function execute(LoginWithPasswordInput $input): AuthSessionData
    {
        [$user, $identityType, $identityHash] = $this->resolveIdentity($input);
        $ipHash = $this->protector->opaqueHash($input->clientIp);
        $this->rateLimiter->assertAllowed($identityHash, $ipHash);

        if (!$this->passwords->verify($input->password, $user?->passwordHash)) {
            $this->rateLimiter->recordFailure($identityHash, $ipHash);
            $this->auth->recordLoginFailure(
                $user,
                $identityType,
                $identityHash,
                $input->device,
                $input->clientIp,
                $input->userAgent,
                'INVALID_CREDENTIALS',
                time(),
            );
            throw new BusinessException('AUTH_INVALID_CREDENTIALS', '账号或密码错误', 401);
        }

        if ($user === null) {
            throw new BusinessException('AUTH_INVALID_CREDENTIALS', '账号或密码错误', 401);
        }
        $this->assertUserCanLogin($user);

        $now = time();
        $session = $this->transactions->run(fn () => $this->auth->createLoginSession(
            $user,
            $input->device,
            $identityType,
            $identityHash,
            $input->clientIp,
            $input->userAgent,
            $now,
        ));
        $this->rateLimiter->clear($identityHash, $ipHash);

        return new AuthSessionData(
            $this->accessTokens->issue($user->userId, $session->sessionId, $input->device->deviceId, $now),
            $this->accessTokens->ttlSeconds(),
            $session->refreshToken,
            $session->refreshExpiresIn,
            $session->sessionId,
            $user->apiSummary(),
        );
    }

    /**
     * @return array{0:?AuthenticatedUser,1:int,2:string}
     */
    private function resolveIdentity(LoginWithPasswordInput $input): array
    {
        $account = trim($input->account);
        if (filter_var($account, FILTER_VALIDATE_EMAIL) !== false) {
            $contact = $this->normalizer->normalize(AuthChannel::Email, $account, null);
            $protected = $this->protector->protect($contact);
            return [$this->auth->findByContact($protected), 20, bin2hex($protected->valueHash)];
        }

        if (str_starts_with($account, '+') || preg_match('/^[0-9 ()-]+$/', $account) === 1) {
            try {
                $contact = $this->normalizer->normalize(AuthChannel::Phone, $account, $input->countryCode);
            } catch (ValidationException) {
                return [null, 10, $this->protector->opaqueHash('invalid:' . $account)];
            }
            $protected = $this->protector->protect($contact);
            return [$this->auth->findByContact($protected), 10, bin2hex($protected->valueHash)];
        }

        $username = strtolower(ltrim($account, '@'));
        if (preg_match('/^[a-z][a-z0-9_]{4,31}$/', $username) !== 1) {
            return [null, 30, $this->protector->opaqueHash('invalid:' . $account)];
        }
        $identityHash = $this->protector->opaqueHash('username:' . $username);

        return [$this->auth->findByUsername($username), 30, $identityHash];
    }

    /**
     * 将账号状态映射为是否允许登录及稳定业务错误。
     */
    private function assertUserCanLogin(AuthenticatedUser $user): void
    {
        if ($user->status === UserStatus::Active) {
            return;
        }

        throw match ($user->status) {
            UserStatus::Locked => new BusinessException('ACCOUNT_LOCKED', '账号已锁定', 403),
            UserStatus::PendingDelete => new BusinessException('ACCOUNT_PENDING_DELETE', '账号处于注销冷静期', 403),
            UserStatus::Deleted, UserStatus::Disabled => new BusinessException('ACCOUNT_DISABLED', '账号不可用', 403),
            default => new BusinessException('ACCOUNT_DISABLED', '账号不可用', 403),
        };
    }
}

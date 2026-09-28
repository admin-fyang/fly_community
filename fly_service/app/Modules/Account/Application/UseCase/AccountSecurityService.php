<?php

declare(strict_types=1);

namespace app\Modules\Account\Application\UseCase;

use app\enum\UserStatus;
use app\exception\BusinessException;
use app\model\AppAccountDeletionRequestModel;
use app\model\AppAuthAuditModel;
use app\model\AppUserModel;
use app\model\AppUserSessionModel;
use app\Modules\Account\Application\Service\ContactNormalizer;
use app\Modules\Account\Application\Service\ContactProtector;
use app\Modules\Account\Application\Service\PasswordHasher;
use app\Modules\Account\Application\Service\VerificationCodeHasher;
use app\Modules\Account\Domain\Enum\AuthChannel;
use app\Modules\Account\Domain\Enum\VerificationScene;
use app\Modules\Account\Domain\Repository\AuthRepository;
use app\Modules\Account\Domain\Repository\VerificationCodeRepository;
use app\Support\Auth\AuthContext;
use app\Support\Id\IdGenerator;
use app\Support\Request\RequestContext;
use app\Support\Transaction\TransactionManager;

/**
 * 找回密码、修改密码与账号注销冷静期应用服务。
 */
final class AccountSecurityService
{
    private const DELETION_COOLING_SECONDS = 30 * 86400;

    /** 注入账号查询、验证码、密码、事务和ID能力。 */
    public function __construct(
        private readonly ContactNormalizer $normalizer,
        private readonly ContactProtector $protector,
        private readonly VerificationCodeHasher $codeHasher,
        private readonly VerificationCodeRepository $verificationCodes,
        private readonly PasswordHasher $passwords,
        private readonly AuthRepository $auth,
        private readonly TransactionManager $transactions,
        private readonly IdGenerator $ids,
        private readonly int $maxVerificationAttempts,
    ) {
    }

    /** 验证找回密码验证码，更新密码并撤销全部设备会话。 */
    public function resetPassword(array $input, string $ip, string $userAgent): array
    {
        $contact = $this->normalizer->normalize($input['channel'], $input['account'], $input['country_code']);
        $protected = $this->protector->protect($contact);
        $scene = $input['channel'] === AuthChannel::Phone ? VerificationScene::ResetPasswordPhone : VerificationScene::ResetPasswordEmail;
        $this->verificationCodes->consume($input['verification_request_id'], $scene, $this->protector->targetHash($contact), $this->codeHasher->hash($input['verification_request_id'], $input['code']), $this->maxVerificationAttempts);
        $user = $this->auth->findByContact($protected);
        if ($user === null) throw new BusinessException('RESOURCE_NOT_FOUND', '账号不存在', 404);
        if ($user->status !== UserStatus::Active) throw new BusinessException('ACCOUNT_UNAVAILABLE', '账号当前不可重置密码', 403);
        $this->passwords->assertStrong($input['new_password']);
        $hash = $this->passwords->hash($input['new_password']);
        $revoked = $this->transactions->run(function () use ($user, $hash, $ip, $userAgent): int {
            $now = time();
            AppUserModel::query()->whereKey($user->userId)->update(['password_hash' => $hash, 'password_changed_at' => $now, 'update_time' => $now]);
            $count = AppUserSessionModel::query()->where('user_id', $user->userId)->whereNull('revoked_at')->update(['revoked_at' => $now, 'revoke_reason' => 'password_reset']);
            $this->audit('password_reset', $user->userId, null, null, $ip, $userAgent, $now);
            return $count;
        });
        return ['revoked_session_count' => $revoked, 'current_session_preserved' => false];
    }

    /** 校验当前密码，更新密码并仅保留当前设备会话。 */
    public function changePassword(AuthContext $auth, array $input, string $ip, string $userAgent): array
    {
        $user = AppUserModel::query()->find($auth->userId);
        if ($user === null || !$this->passwords->verify($input['current_password'], $user->password_hash)) throw new BusinessException('CURRENT_PASSWORD_INVALID', '当前密码不正确', 422);
        $this->passwords->assertStrong($input['new_password']);
        $hash = $this->passwords->hash($input['new_password']);
        $revoked = $this->transactions->run(function () use ($auth, $hash, $ip, $userAgent): int {
            $now = time();
            AppUserModel::query()->whereKey($auth->userId)->update(['password_hash' => $hash, 'password_changed_at' => $now, 'update_time' => $now]);
            $count = AppUserSessionModel::query()->where('user_id', $auth->userId)->where('session_id', '<>', $auth->sessionId)->whereNull('revoked_at')->update(['revoked_at' => $now, 'revoke_reason' => 'password_changed_other_device']);
            $this->audit('password_change', $auth->userId, $auth->sessionId, $auth->deviceId, $ip, $userAgent, $now);
            return $count;
        });
        return ['revoked_session_count' => $revoked];
    }

    /** 仅接受当前密码申请注销，进入30天冷静期。 */
    public function requestDeletion(AuthContext $auth, string $currentPassword, string $ip, string $userAgent): array
    {
        $user = AppUserModel::query()->find($auth->userId);
        if ($user === null || !$this->passwords->verify($currentPassword, $user->password_hash)) throw new BusinessException('CURRENT_PASSWORD_INVALID', '当前密码不正确', 422);
        return $this->transactions->run(function () use ($auth, $ip, $userAgent): array {
            $existing = AppAccountDeletionRequestModel::query()->where('user_id', $auth->userId)->where('status', 10)->lockForUpdate()->first();
            if ($existing !== null) return $this->deletionData($existing);
            $now = time(); $effectiveAt = $now + self::DELETION_COOLING_SECONDS;
            $row = AppAccountDeletionRequestModel::query()->create(['deletion_request_id' => $this->externalId('del'), 'user_id' => $auth->userId, 'status' => 10, 'requested_at' => $now, 'effective_at' => $effectiveAt, 'cancelled_at' => null, 'create_time' => $now, 'update_time' => $now]);
            AppUserModel::query()->whereKey($auth->userId)->update(['status' => UserStatus::PendingDelete->value, 'delete_requested_at' => $now, 'delete_scheduled_at' => $effectiveAt, 'update_time' => $now]);
            $this->audit('account_deletion_requested', $auth->userId, $auth->sessionId, $auth->deviceId, $ip, $userAgent, $now);
            return $this->deletionData($row);
        });
    }

    /** 冷静期内幂等取消注销并恢复正常账号状态。 */
    public function cancelDeletion(AuthContext $auth, string $deletionId, string $ip, string $userAgent): array
    {
        return $this->transactions->run(function () use ($auth, $deletionId, $ip, $userAgent): array {
            $row = AppAccountDeletionRequestModel::query()->where('user_id', $auth->userId)->whereKey($deletionId)->lockForUpdate()->first();
            if ($row === null) throw new BusinessException('RESOURCE_NOT_FOUND', '注销申请不存在', 404);
            if ((int)$row->status === 20) return $this->deletionData($row);
            if ((int)$row->status !== 10 || (int)$row->effective_at <= time()) throw new BusinessException('ACCOUNT_DELETION_NOT_CANCELLABLE', '注销申请已无法取消', 409);
            $now = time(); $row->status = 20; $row->cancelled_at = $now; $row->update_time = $now; $row->save();
            AppUserModel::query()->whereKey($auth->userId)->update(['status' => UserStatus::Active->value, 'delete_requested_at' => null, 'delete_scheduled_at' => null, 'update_time' => $now]);
            $this->audit('account_deletion_cancelled', $auth->userId, $auth->sessionId, $auth->deviceId, $ip, $userAgent, $now);
            return $this->deletionData($row);
        });
    }

    /** 构造注销冷静期公开响应。 */
    private function deletionData(AppAccountDeletionRequestModel $row): array
    {
        return ['deletion_request_id' => $row->deletion_request_id, 'effective_at' => (int)$row->effective_at, 'can_cancel_before' => (int)$row->effective_at, 'status' => [10 => 'pending', 20 => 'cancelled', 30 => 'effective'][(int)$row->status]];
    }

    /** 写入不包含密码、验证码和账号原文的认证安全审计。 */
    private function audit(string $event, int $userId, ?string $sessionId, ?string $deviceId, string $ip, string $userAgent, int $now): void
    {
        AppAuthAuditModel::query()->create(['request_id' => RequestContext::requestId() ?: $this->ids->requestId(), 'event' => $event, 'result' => 10, 'user_id' => $userId, 'identity_type' => null, 'identity_hash' => null, 'session_id' => $sessionId, 'device_id' => $deviceId, 'ip' => $ip, 'user_agent' => mb_substr($userAgent, 0, 512), 'reason_code' => null, 'context' => null, 'create_time' => $now]);
    }

    /** 生成带业务前缀的注销申请ID。 */
    private function externalId(string $prefix): string { return $prefix . '_' . str_replace('-', '', $this->ids->uuidV4()); }
}

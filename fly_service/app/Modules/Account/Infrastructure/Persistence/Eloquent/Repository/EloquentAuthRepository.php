<?php

declare(strict_types=1);

namespace app\Modules\Account\Infrastructure\Persistence\Eloquent\Repository;

use app\Modules\Account\Domain\DTO\AuthenticatedUser;
use app\Modules\Account\Domain\DTO\CreatedSession;
use app\Modules\Account\Domain\DTO\DeviceData;
use app\Modules\Account\Domain\DTO\RegisteredAccount;
use app\Modules\Account\Domain\Exception\GeneratedIdentityCollisionException;
use app\Modules\Account\Domain\Repository\AuthRepository;
use app\Modules\Account\Domain\ValueObject\ProtectedContact;
use app\exception\BusinessException;
use app\enum\UserStatus;
use app\Modules\Account\Infrastructure\Security\RefreshTokenFactory;
use app\model\AppAuthAuditModel;
use app\model\AppDeviceModel;
use app\model\AppUserContactModel;
use app\model\AppUserDeviceModel;
use app\model\AppUserModel;
use app\model\AppUserSessionModel;
use app\model\AppUserSessionTokenModel;
use app\Support\Id\IdGenerator;
use app\Support\Request\RequestContext;
use Illuminate\Database\QueryException;
use Illuminate\Database\Capsule\Manager;

/**
 * 认证模块 Eloquent 仓储。
 */
final class EloquentAuthRepository implements AuthRepository
{
    /**
     * 注入随机ID和Refresh Token生成能力。
     */
    public function __construct(
        private readonly IdGenerator $ids,
        private readonly RefreshTokenFactory $refreshTokens,
    ) {
    }

    /**
     * 根据联系方式类型和HMAC查询唯一绑定关系。
     */
    public function contactExists(ProtectedContact $contact): bool
    {
        return AppUserContactModel::query()
            ->where('contact_type', $contact->type->value)
            ->where('value_hash', $contact->valueHash)
            ->exists();
    }

    /**
     * 根据数据库唯一索引使用的规范值判断用户名是否已被占用。
     */
    public function usernameExists(string $username): bool
    {
        return AppUserModel::query()->where('username', $username)->exists();
    }

    /**
     * 创建用户、联系方式、设备、会话和注册审计。
     *
     * 调用方必须在事务中执行本方法。
     *
     * @param list<ProtectedContact> $contacts 已通过验证码校验的联系方式
     */
    public function createRegisteredUser(
        string $username,
        string $nickname,
        array $contacts,
        string $passwordHash,
        string $publicId,
        ?string $inviterUsername,
        DeviceData $device,
        string $ip,
        string $userAgent,
        int $now,
    ): RegisteredAccount {
        try {
            $inviterId = $inviterUsername === null
                ? null
                : AppUserModel::query()
                    ->where('username', $inviterUsername)
                    ->where('status', UserStatus::Active->value)
                    ->value('user_id');

            if ($inviterUsername !== null && $inviterId === null) {
                throw new BusinessException('INVITE_CODE_INVALID', '邀请码无效', 422);
            }

            $user = AppUserModel::query()->create([
                'public_id' => $publicId,
                'username' => $username,
                'name' => $nickname,
                'first_name' => $nickname,
                'last_name' => null,
                'avatar_resource' => null,
                'motto' => null,
                'sex' => 0,
                'birthday' => null,
                'region_code' => null,
                'birthday_visibility' => 20,
                'phone_visibility' => 20,
                'last_seen_visibility' => 20,
                'password_hash' => $passwordHash,
                'password_changed_at' => $now,
                'profile_version' => 1,
                'last_active_at' => null,
                'is_auth' => 0,
                'status' => UserStatus::Active->value,
                'invite_user_id' => $inviterId,
                'register_ip' => $ip,
                'last_login_at' => $now,
                'last_login_ip' => $ip,
                'login_count' => 1,
                'create_time' => $now,
                'update_time' => $now,
                'delete_requested_at' => null,
                'delete_scheduled_at' => null,
                'delete_time' => null,
                'username_release_at' => null,
            ]);

            foreach ($contacts as $contact) {
                AppUserContactModel::query()->create([
                    'user_id' => $user->user_id,
                    'contact_type' => $contact->type->value,
                    'value_hash' => $contact->valueHash,
                    'value_ciphertext' => $contact->ciphertext,
                    'cipher_key_version' => $contact->cipherKeyVersion,
                    'value_masked' => $contact->masked,
                    'verified_at' => $now,
                    'create_time' => $now,
                    'update_time' => $now,
                ]);
            }

            $this->upsertDevice($user->user_id, $device, $ip, $now);
            $session = $this->insertSession($user->user_id, $device, $ip, $userAgent, $now);
            $this->audit(
                'register',
                10,
                $user->user_id,
                null,
                null,
                $session->sessionId,
                $device->deviceId,
                $ip,
                $userAgent,
                null,
                $now,
            );

            return new RegisteredAccount($this->mapUser($user), $session);
        } catch (QueryException $exception) {
            $message = $exception->getMessage();
            if (str_contains($message, 'uniq_contact_value')) {
                throw new BusinessException('CONTACT_ALREADY_REGISTERED', '该联系方式已注册', 409);
            }
            if (str_contains($message, 'uniq_user_username')) {
                throw new BusinessException('USERNAME_ALREADY_USED', '用户名已被使用', 409);
            }
            if (str_contains($message, 'uniq_user_public_id')) {
                throw new GeneratedIdentityCollisionException(previous: $exception);
            }
            throw $exception;
        }
    }

    /**
     * 通过联系方式HMAC关联查询认证用户快照。
     */
    public function findByContact(ProtectedContact $contact): ?AuthenticatedUser
    {
        $user = AppUserModel::query()
            ->select('app_user.*')
            ->join('app_user_contact', 'app_user_contact.user_id', '=', 'app_user.user_id')
            ->where('app_user_contact.contact_type', $contact->type->value)
            ->where('app_user_contact.value_hash', $contact->valueHash)
            ->first();

        return $user === null ? null : $this->mapUser($user);
    }

    /**
     * 通过唯一规范化用户名查询认证用户快照。
     */
    public function findByUsername(string $username): ?AuthenticatedUser
    {
        $user = AppUserModel::query()->where('username', $username)->first();
        return $user === null ? null : $this->mapUser($user);
    }

    /**
     * 更新设备使用记录，创建登录会话并写入成功审计。
     */
    public function createLoginSession(
        AuthenticatedUser $user,
        DeviceData $device,
        int $identityType,
        string $identityHash,
        string $ip,
        string $userAgent,
        int $now,
    ): CreatedSession {
        $this->upsertDevice($user->userId, $device, $ip, $now);
        AppUserModel::query()->whereKey($user->userId)->update([
            'last_login_at' => $now,
            'last_login_ip' => $ip,
            'login_count' => Manager::raw('login_count + 1'),
            'update_time' => $now,
        ]);
        $session = $this->insertSession($user->userId, $device, $ip, $userAgent, $now);
        $this->audit(
            'login_password',
            10,
            $user->userId,
            $identityType,
            hex2bin($identityHash) ?: null,
            $session->sessionId,
            $device->deviceId,
            $ip,
            $userAgent,
            null,
            $now,
        );

        return $session;
    }

    /**
     * 写入不包含原始账号值的密码登录失败审计。
     */
    public function recordLoginFailure(
        ?AuthenticatedUser $user,
        int $identityType,
        string $identityHash,
        DeviceData $device,
        string $ip,
        string $userAgent,
        string $reasonCode,
        int $now,
    ): void {
        $this->audit(
            'login_password',
            20,
            $user?->userId,
            $identityType,
            hex2bin($identityHash) ?: null,
            null,
            $device->deviceId,
            $ip,
            $userAgent,
            $reasonCode,
            $now,
        );
    }

    /**
     * 幂等写入安装实例和用户设备关系，并保留首次出现时间。
     */
    private function upsertDevice(int $userId, DeviceData $device, string $ip, int $now): void
    {
        AppDeviceModel::query()->upsert([
            [
                'device_id' => $device->deviceId,
                'platform' => $device->platform,
                'device_name' => $device->deviceName,
                'app_version' => $device->appVersion,
                'create_time' => $now,
                'update_time' => $now,
            ],
        ], ['device_id'], ['platform', 'device_name', 'app_version', 'update_time']);

        AppUserDeviceModel::query()->upsert([
            [
                'user_id' => $userId,
                'device_id' => $device->deviceId,
                'trusted_at' => null,
                'first_seen_at' => $now,
                'last_seen_at' => $now,
                'last_ip' => $ip,
                'status' => 10,
            ],
        ], ['user_id', 'device_id'], ['last_seen_at', 'last_ip', 'status']);
    }

    /**
     * 创建会话和首个只保存HMAC的Refresh Token记录。
     */
    private function insertSession(int $userId, DeviceData $device, string $ip, string $userAgent, int $now): CreatedSession
    {
        $sessionId = $this->ids->uuidV4();
        $refresh = $this->refreshTokens->create($sessionId);
        $expiresAt = $now + $refresh['expires_in'];

        AppUserSessionModel::query()->create([
            'session_id' => $sessionId,
            'user_id' => $userId,
            'device_id' => $device->deviceId,
            'device_name' => $device->deviceName,
            'platform' => $device->platform,
            'app_version' => $device->appVersion,
            'created_at' => $now,
            'last_active_at' => $now,
            'expires_at' => $expiresAt,
            'revoked_at' => null,
            'revoke_reason' => null,
            'login_ip' => $ip,
            'user_agent' => mb_substr($userAgent, 0, 512),
        ]);

        AppUserSessionTokenModel::query()->create([
            'token_id' => $refresh['token_id'],
            'session_id' => $sessionId,
            'token_hash' => $refresh['hash'],
            'token_version' => 1,
            'issued_at' => $now,
            'expires_at' => $expiresAt,
            'consumed_at' => null,
            'reused_at' => null,
        ]);

        return new CreatedSession($sessionId, $refresh['token'], $refresh['expires_in']);
    }

    /**
     * 将Eloquent模型裁剪为领域认证用户快照。
     */
    private function mapUser(AppUserModel $user): AuthenticatedUser
    {
        return new AuthenticatedUser(
            $user->user_id,
            $user->public_id,
            $user->name,
            $user->avatar_resource,
            $user->username,
            (bool) $user->is_auth,
            (string) $user->password_hash,
            $user->status,
        );
    }

    /**
     * 以白名单字段写入不可变认证安全审计。
     */
    private function audit(
        string $event,
        int $result,
        ?int $userId,
        ?int $identityType,
        ?string $identityHash,
        ?string $sessionId,
        ?string $deviceId,
        string $ip,
        string $userAgent,
        ?string $reasonCode,
        int $now,
    ): void {
        AppAuthAuditModel::query()->create([
            'request_id' => RequestContext::requestId() ?: $this->ids->requestId(),
            'event' => $event,
            'result' => $result,
            'user_id' => $userId,
            'identity_type' => $identityType,
            'identity_hash' => $identityHash,
            'session_id' => $sessionId,
            'device_id' => $deviceId,
            'ip' => $ip,
            'user_agent' => mb_substr($userAgent, 0, 512),
            'reason_code' => $reasonCode,
            'context' => null,
            'create_time' => $now,
        ]);
    }
}

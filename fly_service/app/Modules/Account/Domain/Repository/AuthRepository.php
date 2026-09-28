<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\Repository;

use app\Modules\Account\Domain\DTO\AuthenticatedUser;
use app\Modules\Account\Domain\DTO\CreatedSession;
use app\Modules\Account\Domain\DTO\DeviceData;
use app\Modules\Account\Domain\DTO\RegisteredAccount;
use app\Modules\Account\Domain\ValueObject\ProtectedContact;

interface AuthRepository
{
    /**
     * 判断规范化用户名是否已经被占用。
     */
    public function usernameExists(string $username): bool;

    /**
     * 判断规范化联系方式是否已绑定用户。
     */
    public function contactExists(ProtectedContact $contact): bool;

    /**
     * 原子注册用户并创建首个登录会话。
     *
     * @param list<ProtectedContact> $contacts 已完成验证码校验的联系方式
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
    ): RegisteredAccount;

    /**
     * 按手机号或邮箱查询认证用户快照。
     */
    public function findByContact(ProtectedContact $contact): ?AuthenticatedUser;

    /**
     * 按规范化用户名查询认证用户快照。
     */
    public function findByUsername(string $username): ?AuthenticatedUser;

    /**
     * 为密码校验成功的用户创建设备关系和新会话。
     */
    public function createLoginSession(
        AuthenticatedUser $user,
        DeviceData $device,
        int $identityType,
        string $identityHash,
        string $ip,
        string $userAgent,
        int $now,
    ): CreatedSession;

    /**
     * 写入不包含原始登录标识的失败安全审计。
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
    ): void;
}

<?php

declare(strict_types=1);

namespace app\Modules\Account\Domain\DTO;

use app\enum\UserStatus;

/**
 * 登录查询返回的最小用户快照，不暴露 Eloquent Model。
 */
final readonly class AuthenticatedUser
{
    /**
     * 创建认证流程使用的最小用户快照。
     */
    public function __construct(
        public int $userId,
        public string $publicId,
        public string $name,
        public ?string $avatarResource,
        public ?string $username,
        public bool $verified,
        public string $passwordHash,
        public UserStatus $status,
    ) {
    }

    /**
     * @return array<string, mixed>
     */
    public function apiSummary(): array
    {
        return [
            'id' => (string) $this->userId,
            'public_id' => $this->publicId,
            'name' => $this->name,
            'avatar_url' => $this->avatarResource,
            'username' => $this->username === null ? null : '@' . $this->username,
            'verified' => $this->verified,
        ];
    }
}

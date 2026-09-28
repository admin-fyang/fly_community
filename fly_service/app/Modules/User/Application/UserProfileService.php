<?php

declare(strict_types=1);

namespace app\Modules\User\Application;

use app\enum\ContactType;
use app\enum\MessageEventType;
use app\Modules\Im\Application\ImEventWriter;
use app\Support\Transaction\TransactionManager;
use app\exception\BusinessException;
use app\Modules\Account\Application\Service\UsernamePolicy;
use app\model\AppFileModel;
use app\model\AppUserContactModel;
use app\model\AppUserModel;
use Illuminate\Database\Capsule\Manager;
use Illuminate\Database\QueryException;
use app\Support\Link\PublicLinkService;

/**
 * 当前用户资料读取、乐观锁修改和头像资源绑定服务。
 */
final class UserProfileService
{
    /**
     * 注入资料规则、事务和用户事件写入器，保证资料与同步事实原子提交。
     */
    public function __construct(
        private readonly PublicLinkService $publicLinks,
        private readonly UsernamePolicy $usernames,
        private readonly TransactionManager $transactions,
        private readonly ImEventWriter $events,
    ) {
    }

    /**
     * 返回当前用户资料白名单。
     *
     * @return array<string, mixed>
     */
    public function show(int $userId): array
    {
        $user = AppUserModel::query()->whereKey($userId)->first();
        if ($user === null) {
            throw new BusinessException('USER_NOT_FOUND', '用户不存在', 404);
        }

        $contacts = AppUserContactModel::query()
            ->where('user_id', $userId)
            ->get(['contact_type', 'value_masked', 'verified_at'])
            ->keyBy(static fn (AppUserContactModel $contact): int => $contact->contact_type->value);
        $avatarUrl = null;
        if ($user->avatar_resource !== null) {
            $avatarUrl = AppFileModel::query()
                ->where('resource_id', $user->avatar_resource)
                ->where('status', 20)
                ->value('src');
        }

        $phone = $contacts->get(ContactType::Phone->value);
        $email = $contacts->get(ContactType::Email->value);

        $username = $user->username === null ? null : (string)$user->username;

        return [
            'id' => (string) $user->user_id,
            'public_id' => $user->public_id,
            'name' => $user->name,
            'first_name' => $user->first_name,
            'last_name' => $user->last_name,
            'avatar_url' => $avatarUrl,
            'username' => $username === null ? null : '@' . $username,
            'profile_path' => $username === null ? null : $this->publicLinks->userPath($username),
            'profile_url' => $username === null ? null : $this->publicLinks->userUrl($username),
            'bio' => $user->motto,
            'sex' => $user->sex,
            'birthday' => $user->birthday,
            'region_code' => $user->region_code,
            'birthday_visibility' => $user->birthday_visibility,
            'phone_visibility' => $user->phone_visibility,
            'last_seen_visibility' => $user->last_seen_visibility,
            'phone' => $phone?->value_masked,
            'phone_verified' => $phone !== null,
            'email' => $email?->value_masked,
            'email_verified' => $email !== null,
            'verified' => $user->is_auth === 1,
            'status' => $user->status->value,
            'created_at' => $user->create_time,
            'profile_version' => $user->profile_version,
        ];
    }

    /**
     * 按资料版本原子更新允许修改的字段。
     *
     * @param array<string, mixed> $input
     * @return array<string, mixed>
     */
    public function update(int $userId, array $input): array
    {
        return $this->transactions->run(function () use ($userId, $input): array {
            $version = $input['profile_version'];
            unset($input['profile_version']);
            // 锁定主档，使合成姓名、版本与事件快照属于同一次更新。
            $user = AppUserModel::query()->whereKey($userId)->lockForUpdate()->first();
            if ($user === null) {
                throw new BusinessException('USER_NOT_FOUND', '用户不存在', 404);
            }

            $updates = $this->validatedUpdates($input, $user);
            $updates['profile_version'] = $version + 1;
            $updates['update_time'] = time();

            try {
                $affected = AppUserModel::query()
                    ->whereKey($userId)
                    ->where('profile_version', $version)
                    ->update($updates);
            } catch (QueryException $exception) {
                if (str_contains($exception->getMessage(), 'uniq_user_username')) {
                    throw new BusinessException('USERNAME_ALREADY_USED', '用户名已被使用', 409);
                }
                throw $exception;
            }
            if ($affected !== 1) {
                throw new BusinessException('PROFILE_VERSION_CONFLICT', '资料已被其他请求修改', 409);
            }

            return $this->recordUpdatedProfile($userId);
        });
    }

    /**
     * 绑定属于当前用户且已确认上传完成的头像资源。
     *
     * @return array<string, mixed>
     */
    public function bindAvatar(int $userId, string $resourceId): array
    {
        return $this->transactions->run(function () use ($userId, $resourceId): array {
            if (AppUserModel::query()->whereKey($userId)->lockForUpdate()->first() === null) {
                throw new BusinessException('USER_NOT_FOUND', '用户不存在', 404);
            }
            $resource = AppFileModel::query()
                ->where('resource_id', $resourceId)
                ->where('user_id', $userId)
                ->where('purpose', 'avatar')
                ->where('status', 20)
                ->first();
            if ($resource === null) {
                throw new BusinessException('FILE_RESOURCE_INVALID', '头像资源不存在或尚未完成上传', 422);
            }

            AppUserModel::query()->whereKey($userId)->update([
                'avatar_resource' => $resourceId,
                'profile_version' => Manager::raw('profile_version + 1'),
                'update_time' => time(),
            ]);
            return $this->recordUpdatedProfile($userId);
        });
    }

    /**
     * 在调用方已锁定用户主档的业务事务内固化本人资料快照。
     * 仅写本人私有频道；不使用后台详情，避免明文联系方式进入事件。
     * @return array<string,mixed> 与实时事件完全一致的资料响应
     */
    public function recordUpdatedProfile(int $userId): array
    {
        if (Manager::connection()->transactionLevel() < 1) {
            throw new \LogicException('资料同步事件必须在业务事务内写入');
        }
        $profile = $this->show($userId);
        $this->events->write($userId, MessageEventType::UserProfileUpdated, null, null, ['user' => $profile], time());
        return $profile;
    }

    /**
     * 校验业务字段并转换为数据库列。
     *
     * @param array<string, mixed> $input
     * @return array<string, mixed>
     */
    private function validatedUpdates(array $input, AppUserModel $user): array
    {
        $updates = [];
        if (array_key_exists('first_name', $input)) {
            if ($input['first_name'] === null || mb_strlen($input['first_name']) < 1 || mb_strlen($input['first_name']) > 64) {
                throw new BusinessException('VALIDATION_ERROR', 'first_name 长度必须为1至64字符', 422);
            }
            $updates['first_name'] = $input['first_name'];
        }
        if (array_key_exists('last_name', $input)) {
            $value = $input['last_name'] === '' ? null : $input['last_name'];
            if ($value !== null && mb_strlen($value) > 64) {
                throw new BusinessException('VALIDATION_ERROR', 'last_name 最多64字符', 422);
            }
            $updates['last_name'] = $value;
        }
        if (isset($updates['first_name']) || array_key_exists('last_name', $updates)) {
            $firstName = $updates['first_name'] ?? $user->first_name;
            $lastName = array_key_exists('last_name', $updates) ? $updates['last_name'] : $user->last_name;
            $updates['name'] = trim($firstName . ' ' . ($lastName ?? ''));
        }
        if (array_key_exists('username', $input)) {
            $username = $input['username'] === null || $input['username'] === '' ? null : strtolower(ltrim(trim($input['username']), '@'));
            // 已有标识未变时不追溯保留词，允许官方账号继续保存其他资料。
            if ($username !== null && $username !== $user->username) {
                try {
                    $username = $this->usernames->normalize($username);
                } catch (BusinessException $exception) {
                    if ($exception->businessCode() !== 'USERNAME_INVALID') throw $exception;
                    // 保留资料修改入口原有的用户名校验状态码，注册与可用性入口仍使用422。
                    throw new BusinessException($exception->businessCode(), $exception->getMessage(), 400);
                }
            }
            $updates['username'] = $username;
        }
        if (array_key_exists('bio', $input)) {
            $bio = $input['bio'] === '' ? null : $input['bio'];
            if ($bio !== null && mb_strlen($bio) > 500) {
                throw new BusinessException('VALIDATION_ERROR', 'bio 最多500字符', 422);
            }
            $updates['motto'] = $bio;
        }
        foreach (['sex' => [0, 1, 2], 'birthday_visibility' => [10, 20, 30], 'phone_visibility' => [10, 20, 30], 'last_seen_visibility' => [10, 20, 30]] as $field => $allowed) {
            if (array_key_exists($field, $input)) {
                if (!in_array($input[$field], $allowed, true)) {
                    throw new BusinessException('VALIDATION_ERROR', "{$field} 取值不受支持", 422);
                }
                $updates[$field] = $input[$field];
            }
        }
        if (array_key_exists('birthday', $input)) {
            $birthday = $input['birthday'] === '' ? null : $input['birthday'];
            if ($birthday !== null && (preg_match('/^\d{4}-\d{2}-\d{2}$/', $birthday) !== 1 || $birthday > date('Y-m-d'))) {
                throw new BusinessException('VALIDATION_ERROR', 'birthday 格式不正确', 422);
            }
            $updates['birthday'] = $birthday;
        }
        if (array_key_exists('region_code', $input)) {
            $region = $input['region_code'] === '' ? null : strtoupper($input['region_code']);
            if ($region !== null && preg_match('/^[A-Z0-9-]{2,32}$/', $region) !== 1) {
                throw new BusinessException('VALIDATION_ERROR', 'region_code 格式不正确', 422);
            }
            $updates['region_code'] = $region;
        }
        if ($updates === []) {
            throw new BusinessException('VALIDATION_ERROR', '没有可修改的资料字段', 422);
        }
        return $updates;
    }
}

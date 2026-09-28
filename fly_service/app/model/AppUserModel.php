<?php

declare(strict_types=1);

namespace app\model;

use app\enum\UserStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * 用户主档数据库模型。
 *
 * @property int $user_id SQL字段：内部用户ID
 * @property string $public_id SQL字段：对外公开且不可修改的FID
 * @property string|null $username SQL字段：公开唯一用户名，仅保存小写且不包含@
 * @property string $name SQL字段：用户对外展示昵称
 * @property string $first_name SQL字段：名字，注册时使用默认昵称
 * @property string|null $last_name SQL字段：姓氏
 * @property string|null $avatar_resource SQL字段：文件模块签发的头像资源标识
 * @property string|null $motto SQL字段：个人简介
 * @property int $sex SQL字段：性别，0未知、1男、2女
 * @property string|null $birthday SQL字段：生日，YYYY-MM-DD
 * @property string|null $region_code SQL字段：国家或行政区标准编码
 * @property int $birthday_visibility SQL字段：生日可见范围，10所有人、20联系人、30仅自己
 * @property int $phone_visibility SQL字段：手机号可见范围，10所有人、20联系人、30仅自己
 * @property int $last_seen_visibility SQL字段：最后在线可见范围，10所有人、20联系人、30仅自己
 * @property string|null $password_hash SQL字段：Argon2id密码哈希完整编码值，仅已匿名化账号为空
 * @property int $password_changed_at SQL字段：最近修改密码时间，Unix秒
 * @property int $profile_version SQL字段：个人资料乐观锁版本号
 * @property int|null $last_active_at SQL字段：最近活跃时间降级值，Unix秒
 * @property int $is_auth SQL字段：官方认证标识，0否、1是
 * @property UserStatus $status SQL字段：账号状态，10正常、20锁定、30待注销、40已注销、50禁用
 * @property int|null $invite_user_id SQL字段：邀请人用户ID
 * @property string|null $register_ip SQL字段：注册IP，支持IPv4和IPv6
 * @property int|null $last_login_at SQL字段：最近成功登录时间，Unix秒
 * @property string|null $last_login_ip SQL字段：最近成功登录IP，支持IPv4和IPv6
 * @property int $login_count SQL字段：成功登录次数
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property int|null $delete_requested_at SQL字段：账号申请注销时间，Unix秒
 * @property int|null $delete_scheduled_at SQL字段：账号计划匿名化时间，Unix秒
 * @property int|null $delete_time SQL字段：账号实际匿名化时间，Unix秒
 * @property int|null $username_release_at SQL字段：匿名化后用户名释放时间，Unix秒
 * @property-read AppFileModel|null $avatarFile 当前已完成的头像文件资源
 */
final class AppUserModel extends Model
{
    protected $table = 'app_user';
    protected $primaryKey = 'user_id';
    public $timestamps = false;
    protected $guarded = ['user_id'];

    protected $casts = [
        'user_id' => 'integer',
        'sex' => 'integer',
        'birthday_visibility' => 'integer',
        'phone_visibility' => 'integer',
        'last_seen_visibility' => 'integer',
        'password_changed_at' => 'integer',
        'profile_version' => 'integer',
        'last_active_at' => 'integer',
        'is_auth' => 'integer',
        'status' => UserStatus::class,
        'invite_user_id' => 'integer',
        'last_login_at' => 'integer',
        'login_count' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
        'delete_requested_at' => 'integer',
        'delete_scheduled_at' => 'integer',
        'delete_time' => 'integer',
        'username_release_at' => 'integer',
    ];

    /**
     * 获取当前已完成的头像文件资源。
     *
     * 关系通过资源标识而非文件主键绑定，供消息历史批量预加载头像，避免逐条查询。
     */
    public function avatarFile(): BelongsTo
    {
        return $this->belongsTo(AppFileModel::class, 'avatar_resource', 'resource_id')
            ->where('status', 20);
    }
}

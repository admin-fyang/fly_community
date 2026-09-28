<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 用户登录会话数据库模型。
 *
 * @property string $session_id SQL字段：登录会话UUID v4
 * @property int $user_id SQL字段：所属用户ID
 * @property string $device_id SQL字段：登录设备UUID v4
 * @property string|null $device_name SQL字段：登录时设备名称快照，历史未知为空
 * @property string|null $platform SQL字段：登录时平台快照
 * @property string|null $app_version SQL字段：登录时客户端版本快照
 * @property int $created_at SQL字段：会话创建时间，Unix秒
 * @property int $last_active_at SQL字段：会话最近活跃时间，Unix秒
 * @property int $expires_at SQL字段：会话绝对过期时间，Unix秒
 * @property int|null $revoked_at SQL字段：会话撤销时间，Unix秒
 * @property string|null $revoke_reason SQL字段：会话撤销原因代码
 * @property string|null $login_ip SQL字段：创建会话时的登录IP
 * @property string|null $user_agent SQL字段：创建会话时的User-Agent
 */
final class AppUserSessionModel extends Model
{
    protected $table = 'app_user_session';
    protected $primaryKey = 'session_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];

    protected $casts = [
        'user_id' => 'integer',
        'created_at' => 'integer',
        'last_active_at' => 'integer',
        'expires_at' => 'integer',
        'revoked_at' => 'integer',
    ];
}

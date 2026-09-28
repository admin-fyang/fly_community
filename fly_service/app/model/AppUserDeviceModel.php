<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * 用户与设备关系数据库模型。
 *
 * @property int $user_id SQL字段：所属用户ID
 * @property string $device_id SQL字段：客户端安装实例UUID v4
 * @property int|null $trusted_at SQL字段：用户确认设备可信的时间，Unix秒
 * @property int $first_seen_at SQL字段：该用户首次登录此设备时间，Unix秒
 * @property int $last_seen_at SQL字段：该用户最近使用此设备时间，Unix秒
 * @property string|null $last_ip SQL字段：设备最近访问IP，支持IPv4和IPv6
 * @property int $status SQL字段：用户设备状态，10正常、20禁用
 */
final class AppUserDeviceModel extends Model
{
    protected $table = 'app_user_device';
    protected $primaryKey = null;
    public $incrementing = false;
    public $timestamps = false;
    protected $guarded = [];

    protected $casts = [
        'user_id' => 'integer',
        'trusted_at' => 'integer',
        'first_seen_at' => 'integer',
        'last_seen_at' => 'integer',
        'status' => 'integer',
    ];
}

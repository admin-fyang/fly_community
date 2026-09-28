<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * IM用户设备同步状态模型。
 *
 * @property int $user_id SQL字段：用户ID
 * @property string $device_id SQL字段：设备ID
 * @property int $last_ack_event_id SQL字段：该设备最后确认处理的事件ID
 * @property int|null $last_sync_at SQL字段：最近同步时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppUserSyncStateModel extends Model
{
    protected $table = 'app_user_sync_state';
    protected $primaryKey = 'user_id';
    public $incrementing = false;
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = [
        'user_id' => 'integer',
        'last_ack_event_id' => 'integer',
        'last_sync_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
}

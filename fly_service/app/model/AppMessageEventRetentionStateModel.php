<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * IM事件全局保留水位模型。
 *
 * @property int $state_id SQL字段：保留水位固定记录ID，恒为1
 * @property int $minimum_event_id SQL字段：服务端保证仍可同步的最小事件ID
 * @property int $update_time SQL字段：保留水位更新时间，Unix秒
 */
final class AppMessageEventRetentionStateModel extends Model
{
    protected $table = 'app_message_event_retention_state';
    protected $primaryKey = 'state_id';
    public $incrementing = false;
    public $timestamps = false;
    protected $guarded = ['state_id'];
    protected $casts = [
        'state_id' => 'integer',
        'minimum_event_id' => 'integer',
        'update_time' => 'integer',
    ];
}

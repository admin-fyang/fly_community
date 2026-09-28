<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * IM用户消息状态模型。
 *
 * @property int $message_id SQL字段：消息ID
 * @property int $user_id SQL字段：用户ID
 * @property int $is_deleted SQL字段：是否仅对该用户删除，0否、1是
 * @property int|null $deleted_at SQL字段：仅对该用户删除时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppMessageUserStateModel extends Model
{
    protected $table = 'app_message_user_state';
    protected $primaryKey = 'message_id';
    public $incrementing = false;
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = [
        'message_id' => 'integer',
        'user_id' => 'integer',
        'is_deleted' => 'integer',
        'deleted_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
}

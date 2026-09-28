<?php

declare(strict_types=1);

namespace app\model;

use app\enum\FriendStatus;
use Illuminate\Database\Eloquent\Model;

/**
 * 好友关系模型。
 *
 * @property int $friend_id SQL字段：好友关系ID
 * @property int $create_user SQL字段：关系所属用户ID
 * @property int $friend_user_id SQL字段：好友用户ID
 * @property string|null $nickname SQL字段：当前用户给好友设置的备注
 * @property int $is_invite SQL字段：历史邀请方标识，0否、1是
 * @property int $is_top SQL字段：是否置顶，0否、1是
 * @property int $is_notice SQL字段：是否消息提醒，0否、1是
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int|null $delete_time SQL字段：删除或拉黑时间，Unix秒
 * @property string|null $remark SQL字段：历史申请备注，新申请统一进入系统通知
 * @property FriendStatus $status SQL字段：好友状态，-2拉黑、-1删除、0历史待同意、1好友
 */
final class AppFriendModel extends Model
{
    protected $table = 'app_friend';
    protected $primaryKey = 'friend_id';
    public $timestamps = false;
    protected $guarded = ['friend_id'];
    protected $casts = [
        'friend_id' => 'integer',
        'create_user' => 'integer',
        'friend_user_id' => 'integer',
        'is_invite' => 'integer',
        'is_top' => 'integer',
        'is_notice' => 'integer',
        'update_time' => 'integer',
        'create_time' => 'integer',
        'delete_time' => 'integer',
        'status' => FriendStatus::class,
    ];
}

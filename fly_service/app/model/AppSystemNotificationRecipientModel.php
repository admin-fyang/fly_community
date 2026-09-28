<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * 系统通知接收人状态模型。
 *
 * @property int $notification_id SQL字段：系统通知ID
 * @property int $recipient_user_id SQL字段：通知接收用户ID
 * @property int $is_read SQL字段：是否已读，0未读、1已读
 * @property int|null $read_at SQL字段：已读时间，Unix秒
 * @property int $is_deleted SQL字段：是否仅对该接收人删除，0否、1是
 * @property int|null $deleted_at SQL字段：仅对该接收人删除时间，Unix秒
 * @property int $last_event_id SQL字段：该通知对该接收人最近同步事件ID
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property-read AppSystemNotificationModel $notification 通知主记录
 */
final class AppSystemNotificationRecipientModel extends Model
{
    protected $table = 'app_system_notification_recipient';
    protected $primaryKey = 'notification_id';
    public $incrementing = false;
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = [
        'notification_id' => 'integer',
        'recipient_user_id' => 'integer',
        'is_read' => 'integer',
        'read_at' => 'integer',
        'is_deleted' => 'integer',
        'deleted_at' => 'integer',
        'last_event_id' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];

    /**
     * 获取通知主记录。
     */
    public function notification(): BelongsTo
    {
        return $this->belongsTo(AppSystemNotificationModel::class, 'notification_id', 'notification_id');
    }
}

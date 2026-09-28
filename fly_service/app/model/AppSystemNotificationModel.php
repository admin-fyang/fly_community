<?php

declare(strict_types=1);

namespace app\model;

use app\enum\NotificationActionStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * 系统通知主表模型。
 *
 * @property int $notification_id SQL字段：系统通知ID，全局唯一
 * @property string $notification_type SQL字段：通知类型，含好友申请、friend_removed_by_admin平台解除、群邀请、群治理、安全提醒和系统公告
 * @property int|null $actor_user_id SQL字段：触发通知的用户ID，系统通知可为空
 * @property string $biz_type SQL字段：业务类型，friend/group/security/system等
 * @property string $biz_id SQL字段：业务对象ID或业务唯一键
 * @property string $dedupe_key SQL字段：通知幂等键，用于识别同一业务通知历史
 * @property string|null $active_dedupe_key SQL字段：待处理通知唯一键，仅action_status为20待处理时有值
 * @property string $title SQL字段：通知标题
 * @property string|null $content SQL字段：通知正文摘要，禁止保存敏感原文
 * @property array<string,mixed>|null $payload SQL字段：通知扩展载荷，保存跳转参数和展示快照
 * @property NotificationActionStatus $action_status SQL字段：通知动作状态，10无需处理、20待处理、30已同意、40已拒绝、50已过期、60已取消
 * @property int|null $handled_by SQL字段：处理人用户ID，未处理为空
 * @property int|null $handled_at SQL字段：处理时间，Unix秒
 * @property int|null $expire_at SQL字段：通知过期时间，Unix秒
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property-read \Illuminate\Database\Eloquent\Collection<int,AppSystemNotificationRecipientModel> $recipients 通知接收人状态集合
 */
final class AppSystemNotificationModel extends Model
{
    protected $table = 'app_system_notification';
    protected $primaryKey = 'notification_id';
    public $timestamps = false;
    protected $guarded = ['notification_id'];
    protected $casts = [
        'notification_id' => 'integer',
        'actor_user_id' => 'integer',
        'payload' => 'array',
        'action_status' => NotificationActionStatus::class,
        'handled_by' => 'integer',
        'handled_at' => 'integer',
        'expire_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];

    /**
     * 获取通知接收人状态集合。
     */
    public function recipients(): HasMany
    {
        return $this->hasMany(AppSystemNotificationRecipientModel::class, 'notification_id', 'notification_id');
    }
}

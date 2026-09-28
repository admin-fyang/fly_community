<?php

declare(strict_types=1);

namespace app\model;

use app\enum\OutboxStatus;
use Illuminate\Database\Eloquent\Model;

/**
 * IM事件发布Outbox模型。
 *
 * @property int $outbox_id SQL字段：Outbox任务ID
 * @property int $event_id SQL字段：待发布的用户收件箱事件ID
 * @property string|null $domain_event_id SQL字段：多收件人共享的V2领域事件ID
 * @property int $protocol_version SQL字段：投递协议版本
 * @property int $user_id SQL字段：事件接收用户ID
 * @property string $channel SQL字段：Centrifugo私有频道名
 * @property array<string,mixed> $payload SQL字段：发布到Centrifugo的完整事件载荷快照
 * @property OutboxStatus $status SQL字段：发布状态，10待发布、20已发布、30失败可重试、40失败死信、50业务失效已跳过
 * @property int $retry_count SQL字段：已重试次数
 * @property int|null $next_retry_at SQL字段：下次重试时间，Unix秒
 * @property string|null $locked_by SQL字段：当前发布任务持有者标识
 * @property int|null $locked_until SQL字段：发布任务锁租约到期时间，Unix秒
 * @property int|null $published_at SQL字段：成功发布时间，Unix秒
 * @property string|null $last_error SQL字段：最近一次脱敏后的发布失败原因
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppMessageEventOutboxModel extends Model
{
    protected $table = 'app_message_event_outbox';
    protected $primaryKey = 'outbox_id';
    public $timestamps = false;
    protected $guarded = ['outbox_id'];
    protected $casts = [
        'outbox_id' => 'integer',
        'event_id' => 'integer',
        'protocol_version' => 'integer',
        'user_id' => 'integer',
        'payload' => 'array',
        'status' => OutboxStatus::class,
        'retry_count' => 'integer',
        'next_retry_at' => 'integer',
        'locked_until' => 'integer',
        'published_at' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
}

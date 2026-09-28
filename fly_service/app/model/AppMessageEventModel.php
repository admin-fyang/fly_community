<?php

declare(strict_types=1);

namespace app\model;

use app\enum\MessageEventType;
use Illuminate\Database\Eloquent\Model;

/**
 * IM用户增量同步事件模型。
 *
 * @property int $event_id SQL字段：用户收件箱事件ID，全局递增
 * @property int $user_id SQL字段：事件接收用户ID
 * @property int|null $conversation_id SQL字段：关联会话ID，非会话事件可为空
 * @property int|null $message_id SQL字段：关联消息ID，非消息事件可为空
 * @property int|null $notification_id SQL字段：关联系统通知ID，非通知事件可为空
 * @property MessageEventType $event_type SQL字段：事件类型，10新消息、20撤回、21平台治理、30仅对我删除、40会话更新、50回执更新、60通话邀请、61通话更新、62群直播更新、63群会议V2、64红包更新、70通知创建、71通知更新、80本人资料更新
 * @property array<string,mixed> $event_payload SQL字段：客户端增量同步所需的最小事件载荷快照
 * @property int $create_time SQL字段：事件创建时间，Unix秒
 */
final class AppMessageEventModel extends Model
{
    protected $table = 'app_message_event';
    protected $primaryKey = 'event_id';
    public $timestamps = false;
    protected $guarded = ['event_id'];
    protected $casts = [
        'event_id' => 'integer',
        'user_id' => 'integer',
        'conversation_id' => 'integer',
        'message_id' => 'integer',
        'notification_id' => 'integer',
        'event_type' => MessageEventType::class,
        'event_payload' => 'array',
        'create_time' => 'integer',
    ];
}

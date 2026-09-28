<?php

declare(strict_types=1);

namespace app\model;

use app\enum\ConversationType;
use Illuminate\Database\Eloquent\Model;

/**
 * IM会话主表模型。
 *
 * @property int $conversation_id SQL字段：会话ID，全局唯一
 * @property ConversationType $conversation_type SQL字段：会话类型，1单聊、2群聊
 * @property int $target_id SQL字段：会话目标ID，单聊暂为0、群聊为群ID
 * @property string $chat_key SQL字段：会话唯一业务键
 * @property int|null $last_message_id SQL字段：最后一条可用于会话预览的消息ID
 * @property int $last_seq SQL字段：当前会话最大消息序号
 * @property int $last_event_id SQL字段：当前会话最近事件ID
 * @property int $status SQL字段：会话状态，10正常、20归档、30不可用
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppConversationModel extends Model
{
    protected $table = 'app_conversation';
    protected $primaryKey = 'conversation_id';
    public $timestamps = false;
    protected $guarded = ['conversation_id'];
    protected $casts = [
        'conversation_id' => 'integer',
        'conversation_type' => ConversationType::class,
        'target_id' => 'integer',
        'last_message_id' => 'integer',
        'last_seq' => 'integer',
        'last_event_id' => 'integer',
        'status' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
}

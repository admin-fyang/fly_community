<?php

declare(strict_types=1);

namespace app\model;

use Illuminate\Database\Eloquent\Model;

/**
 * IM会话成员状态模型。
 *
 * @property int $conversation_id SQL字段：会话ID
 * @property int $user_id SQL字段：用户ID
 * @property int $member_role SQL字段：会话成员角色，10普通成员、20管理员、30群主
 * @property int $join_seq SQL字段：用户加入会话时的消息序号
 * @property int|null $history_end_seq SQL字段：退群时最后可见消息序号，null表示没有离群上界
 * @property int $last_read_seq SQL字段：用户最后已读的会话消息序号
 * @property int $last_mention_seq SQL字段：最后一次被提及的消息序号
 * @property int $cleared_before_seq SQL字段：用户清空聊天记录到此序号
 * @property int $unread_count SQL字段：用户当前未读数
 * @property int $is_pinned SQL字段：是否置顶，0否、1是
 * @property int $is_muted SQL字段：是否免打扰，0否、1是
 * @property int $is_hidden SQL字段：是否在会话列表隐藏，0否、1是
 * @property int $last_event_id SQL字段：该用户在此会话最后可见事件ID
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 */
final class AppConversationMemberModel extends Model
{
    protected $table = 'app_conversation_member';
    protected $primaryKey = 'conversation_id';
    public $incrementing = false;
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = [
        'conversation_id' => 'integer',
        'user_id' => 'integer',
        'member_role' => 'integer',
        'join_seq' => 'integer',
        'history_end_seq' => 'integer',
        'last_read_seq' => 'integer',
        'last_mention_seq' => 'integer',
        'cleared_before_seq' => 'integer',
        'unread_count' => 'integer',
        'is_pinned' => 'integer',
        'is_muted' => 'integer',
        'is_hidden' => 'integer',
        'last_event_id' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];
    /**
     * 成员表的真实主键是会话+用户；实例保存/递增/删除必须同时限定两列。
     * Eloquent默认单列主键会把一个成员的未读、事件游标更新传播到全群。
     */
    protected function setKeysForSaveQuery($query)
    {
        return $this->setKeysForSelectQuery($query);
    }

    /** refresh/fresh同样按原始复合身份读取，不能载入同会话的第一个成员。 */
    protected function setKeysForSelectQuery($query)
    {
        return $query
            ->where('conversation_id', $this->original['conversation_id'] ?? $this->getAttribute('conversation_id'))
            ->where('user_id', $this->original['user_id'] ?? $this->getAttribute('user_id'));
    }
}

<?php

declare(strict_types=1);

namespace app\model;

use app\enum\MessageStatus;
use app\enum\MessageType;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * IM消息主表模型。
 *
 * @property int $message_id SQL字段：消息ID，全局唯一
 * @property int $conversation_id SQL字段：会话ID
 * @property int $seq SQL字段：会话内消息序号
 * @property int $sender_id SQL字段：发送者用户ID
 * @property array<string,mixed> $sender_snapshot SQL字段：发送时的用户全局昵称与头像快照
 * @property string $client_msg_id SQL字段：客户端生成的幂等消息ID
 * @property MessageType $message_type SQL字段：消息类型，text文本、image图片、file文件
 * @property string|null $body_text SQL字段：文本消息正文
 * @property int $mention_all SQL字段：是否提及所有成员
 * @property list<int>|null $mention_user_ids SQL字段：被提及用户ID
 * @property list<array{user_id:string,name:string}>|null $mention_users SQL字段：发送时昵称快照
 * @property string $payload_hash SQL字段：客户端发送载荷SHA-256摘要
 * @property int|null $reply_message_id SQL字段：被引用的同会话原消息ID
 * @property array<string,mixed>|null $reply_snapshot SQL字段：引用消息展示快照
 * @property array<string,mixed>|null $extra SQL字段：低频扩展数据
 * @property MessageStatus $status SQL字段：消息状态，10正常、20已撤回
 * @property int|null $recalled_at SQL字段：撤回时间，Unix秒
 * @property int|null $recalled_by SQL字段：撤回操作者用户ID
 * @property string|null $recall_reason SQL字段：撤回原因或客户端展示文案
 * @property int $create_time SQL字段：创建时间，Unix秒
 * @property int $update_time SQL字段：更新时间，Unix秒
 * @property-read \Illuminate\Database\Eloquent\Collection<int,AppMessageAttachmentModel> $attachments 消息附件集合
 * @property-read AppMessageModel|null $replyTarget 被引用的原消息
 * @property-read AppUserModel $sender 消息发送者用户主档
 */
final class AppMessageModel extends Model
{
    protected $table = 'app_message';
    protected $primaryKey = 'message_id';
    public $timestamps = false;
    protected $guarded = ['message_id'];
    protected $casts = [
        'message_id' => 'integer',
        'conversation_id' => 'integer',
        'seq' => 'integer',
        'sender_id' => 'integer',
        'sender_snapshot' => 'array',
        'mention_all' => 'integer',
        'mention_user_ids' => 'array',
        'mention_users' => 'array',
        'message_type' => MessageType::class,
        'reply_message_id' => 'integer',
        'reply_snapshot' => 'array',
        'extra' => 'array',
        'status' => MessageStatus::class,
        'recalled_at' => 'integer',
        'recalled_by' => 'integer',
        'create_time' => 'integer',
        'update_time' => 'integer',
    ];

    /**
     * 获取消息的有序文件附件。
     */
    public function attachments(): HasMany
    {
        return $this->hasMany(AppMessageAttachmentModel::class, 'message_id', 'message_id')
            ->orderBy('sort_order');
    }

    /**
     * 获取被当前消息引用的原消息。
     */
    public function replyTarget(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reply_message_id', 'message_id');
    }

    /**
     * 获取消息发送者用户主档。
     *
     * 群成员离群只改变成员关系，不影响通过sender_id读取用户当前公开资料。
     */
    public function sender(): BelongsTo
    {
        return $this->belongsTo(AppUserModel::class, 'sender_id', 'user_id');
    }
}

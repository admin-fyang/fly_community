<?php

declare(strict_types=1);

namespace app\enum;

/**
 * IM用户增量同步事件类型。
 */
enum MessageEventType: int
{
    /** 新消息已写入服务端。 */
    case MessageCreated = 10;

    /** 原消息已被撤回。 */
    case MessageRecalled = 20;

    /** 消息已仅对当前用户删除。 */
    case MessageDeletedForMe = 30;

    /** 当前用户的会话状态已变化。 */
    case ConversationUpdated = 40;

    /** 消息已读游标已变化。 */
    case ReceiptUpdated = 50;

    /** 系统通知已创建。 */
    case NotificationCreated = 70;

    /** 系统通知状态已变化。 */
    case NotificationUpdated = 71;

    /** 本人资料已更新，所有本人终端按资料版本应用完整快照。 */
    case UserProfileUpdated = 80;

    /**
     * 返回客户端事件名称。
     */
    public function apiName(): string
    {
        return match ($this) {
            self::MessageCreated => 'message_created',
            self::MessageRecalled => 'message_recalled',
            self::MessageDeletedForMe => 'message_deleted_for_me',
            self::ConversationUpdated => 'conversation_updated',
            self::ReceiptUpdated => 'receipt_updated',
            self::NotificationCreated => 'notification_created',
            self::NotificationUpdated => 'notification_updated',
            self::UserProfileUpdated => 'user_profile_updated',
        };
    }
}

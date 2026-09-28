<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\model\AppConversationMemberModel;
use Illuminate\Database\Capsule\Manager;
use Illuminate\Database\Eloquent\Builder;

/** 群消息授权区间：当前加入区间与已结束区间的并集，清空记录始终优先。 */
final class ConversationHistoryAccess
{
    /** 对消息查询施加同一权限谓词；数据库完成过滤，分页不会跨过未授权间隙。 */
    public static function constrain(Builder $query, AppConversationMemberModel $member): Builder
    {
        $minimum = max((int)$member->cleared_before_seq, (int)$member->join_seq);
        return $query->where('seq', '>', $minimum)
            ->when($member->history_end_seq !== null, static fn (Builder $q) => $q->where('seq', '<=', (int)$member->history_end_seq));
    }

    /** 单聊成员只能查看当前加入位置之后、未清空的消息。 */
    public static function contains(AppConversationMemberModel $member, int $seq): bool
    {
        return $seq > max((int)$member->cleared_before_seq, (int)$member->join_seq)
            && ($member->history_end_seq === null || $seq <= (int)$member->history_end_seq);
    }

    /** 引用属于源消息权限，按接收者裁剪。 */
    public static function redactReply(array $row, int $userId, int $conversationId): array
    {
        $replyId = (int)($row['reply_message_id'] ?? $row['reply']['message_id'] ?? 0);
        if ($replyId <= 0) {
            return $row;
        }
        $member = AppConversationMemberModel::query()->where('conversation_id', $conversationId)->where('user_id', $userId)->first();
        $target = \app\model\AppMessageModel::query()->whereKey($replyId)->where('conversation_id', $conversationId)->first();
        $deleted = Manager::table('app_message_user_state')->where('message_id', $replyId)->where('user_id', $userId)->where('is_deleted', 1)->exists();
        if (!$member instanceof AppConversationMemberModel || $target === null || !self::contains($member, (int)$target->seq) || $deleted) {
            $row['reply_message_id'] = null;
            $row['reply'] = null;
        }
        return $row;
    }

    /** 已持久化用户事件和实时发布使用同一裁剪后载荷，禁止只修HTTP。 */
    public static function redactEventReplies(array $payload, int $userId, ?int $conversationId): array
    {
        if ($conversationId === null) {
            return $payload;
        }
        foreach (['message', 'last_message'] as $key) {
            if (isset($payload[$key]) && is_array($payload[$key])) {
                $payload[$key] = self::redactReply($payload[$key], $userId, $conversationId);
            }
        }
        if (isset($payload['conversation']) && is_array($payload['conversation'])) {
            $payload['conversation'] = self::redactEventReplies($payload['conversation'], $userId, $conversationId);
        }
        return self::redactReply($payload, $userId, $conversationId);
    }
}

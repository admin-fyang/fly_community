<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\MessageEventType;
use app\enum\OutboxStatus;
use app\model\AppMessageEventModel;
use app\model\AppMessageEventOutboxModel;

/**
 * IM用户事件与Outbox原子写入器。
 *
 * 调用者必须处于业务数据库事务中，确保业务事实、同步事件和实时发布任务同时提交。
 */
final class ImEventWriter
{
    /**
     * 写入单个用户事件及其唯一Outbox任务。
     *
     * @param int $userId 事件接收用户ID
     * @param MessageEventType $eventType 事件类型
     * @param int|null $conversationId 关联会话ID
     * @param int|null $messageId 关联消息ID
     * @param array<string,mixed> $payload 客户端所需最小载荷
     * @param int $now 当前Unix秒
     * @return int 新事件ID
     */
    public function write(
        int $userId,
        MessageEventType $eventType,
        ?int $conversationId,
        ?int $messageId,
        array $payload,
        int $now,
    ): int {
        return (int)$this->writeWithEnvelope(
            $userId,
            $eventType,
            $conversationId,
            $messageId,
            $payload,
            $now,
        )['event_id'];
    }

    /**
     * 写入单个用户事件并返回与 Sync、Centrifugo 完全一致的 Event Envelope。
     *
     * Directory Change 的 revision 只能在事件主键生成后确定，因此统一在此处注入，
     * 禁止各业务 Service 使用时间戳或另一个计数器模拟修订号。
     *
     * @param array<string,mixed> $payload 客户端增量载荷
     * @return array<string,mixed> 已持久化的权威 Event Envelope
     */
    public function writeWithEnvelope(
        int $userId,
        MessageEventType $eventType,
        ?int $conversationId,
        ?int $messageId,
        array $payload,
        int $now,
        ?int $notificationId = null,
        ?string $domainEventId = null,
        int $protocolVersion = 1,
    ): array {
        $payload = ConversationHistoryAccess::redactEventReplies($payload, $userId, $conversationId);
        /** @var AppMessageEventModel $event */
        $event = AppMessageEventModel::query()->create([
            'user_id' => $userId,
            'conversation_id' => $conversationId,
            'message_id' => $messageId,
            'notification_id' => $notificationId,
            'event_type' => $eventType->value,
            'event_payload' => $payload,
            'create_time' => $now,
        ]);

        $eventId = (int)$event->event_id;
        $payload = $this->withDirectoryRevision($payload, $eventId);
        if ($payload !== $event->event_payload) {
            $event->event_payload = $payload;
            $event->save();
        }

        $eventEnvelope = [
            'event_id' => (string)$eventId,
            'event_type' => $eventType->apiName(),
            'conversation_id' => $conversationId === null ? null : (string)$conversationId,
            'message_id' => $messageId === null ? null : (string)$messageId,
            'notification_id' => $notificationId === null ? null : (string)$notificationId,
            'occurred_at' => $now,
            // 保留V1字段，旧客户端升级期间仍能读取事件时间；新协议统一使用occurred_at。
            'server_time' => $now,
            'payload' => $payload,
        ];

        AppMessageEventOutboxModel::query()->create([
            'event_id' => $eventId,
            'domain_event_id' => $domainEventId,
            'protocol_version' => $protocolVersion,
            'user_id' => $userId,
            'channel' => 'private-user:' . $userId,
            'payload' => $eventEnvelope,
            'status' => OutboxStatus::Pending->value,
            'retry_count' => 0,
            'next_retry_at' => null,
            'locked_by' => null,
            'locked_until' => null,
            'published_at' => null,
            'last_error' => null,
            'create_time' => $now,
            'update_time' => $now,
        ]);

        return $eventEnvelope;
    }

    /**
     * 写入系统通知用户事件及Outbox任务。
     *
     * @param int $userId 事件接收用户ID
     * @param MessageEventType $eventType 通知事件类型
     * @param int $notificationId 关联系统通知ID
     * @param array<string,mixed> $payload 客户端所需最小载荷
     * @param int $now 当前Unix秒
     * @return int 新事件ID
     */
    public function writeNotification(
        int $userId,
        MessageEventType $eventType,
        int $notificationId,
        array $payload,
        int $now,
    ): int {
        return (int)$this->writeWithEnvelope(
            $userId,
            $eventType,
            null,
            null,
            $payload,
            $now,
            $notificationId,
        )['event_id'];
    }

    /**
     * 写入通话用户事件及Outbox任务。
     *
     * @param int $userId 事件接收用户ID
     * @param MessageEventType $eventType 通话事件类型
     * @param int $conversationId 关联会话ID
     * @param array<string,mixed> $payload 客户端所需最小载荷
     * @param int $now 当前Unix秒
     * @return int 新事件ID
     */
    private function withDirectoryRevision(array $payload, int $eventId): array
    {
        $changes = $payload['directory_changes'] ?? null;
        if (!is_array($changes)) {
            return $payload;
        }

        $payload['directory_changes'] = array_map(
            static function (mixed $change) use ($eventId): mixed {
                if (!is_array($change)) {
                    return $change;
                }
                $change['revision'] = (string)$eventId;
                return $change;
            },
            $changes,
        );

        return $payload;
    }

    /**
     * 在业务事务内为当前有效设备创建离线推送 Outbox，事务回滚时绝不会残留推送任务。
     *
     * 偏好、会话免打扰、设备在线和通话终态属于发送时事实，Worker发送前必须再次校验。
     *
     * @param array<string,mixed> $eventEnvelope 权威事件信封
     */
}

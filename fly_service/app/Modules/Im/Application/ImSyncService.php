<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\MessageEventType;
use app\exception\BusinessException;
use app\model\AppMessageEventModel;
use app\model\AppMessageEventRetentionStateModel;
use app\model\AppUserSyncStateModel;

/**
 * IM用户事件增量同步应用服务。
 */
final class ImSyncService
{
    /**
     * 按用户事件游标返回增量变化。
     *
     * @param int $userId 当前用户ID
     * @param int $afterEventId 客户端已处理的最后事件ID
     * @param int $limit 本次最多返回事件数
     * @return array<string,mixed>
     */
    public function sync(
        int $userId,
        int $afterEventId,
        int $limit,
    ): array {
        $minimumEventId = $this->minimumEventId();
        $this->assertCursorAvailable($afterEventId, $minimumEventId);

        $rows = AppMessageEventModel::query()
            ->where('user_id', $userId)
            ->where('event_id', '>', $afterEventId)
            ->orderBy('event_id')
            ->limit($limit + 1)
            ->get();

        $hasMore = $rows->count() > $limit;
        $events = $rows->take($limit)->values();
        $nextEventId = $events->isEmpty() ? $afterEventId : (int)$events->last()->event_id;
        $now = time();
        $latestEventId = max($afterEventId, (int)(AppMessageEventModel::query()
            ->where('user_id', $userId)
            ->max('event_id') ?? 0));

        return [
            'server_time' => $now,
            'next_event_id' => (string)$nextEventId,
            'latest_event_id' => (string)$latestEventId,
            'minimum_event_id' => (string)$minimumEventId,
            'has_more' => $hasMore,
            'events' => $events
                ->map(fn (AppMessageEventModel $event): array => $this->eventRow($event))
                ->all(),
        ];
    }

    /** 校验同步游标是否仍处于事件保留范围。 */
    private function assertCursorAvailable(int $cursor, int $minimumAvailable): void
    {
        if ($cursor < $minimumAvailable - 1) {
            throw new BusinessException('SYNC_RESET_REQUIRED', '增量事件已超出保留范围，请重新执行目录Bootstrap', 409);
        }
    }

    /**
     * 单调确认当前设备已经完整应用的事件位置。
     *
     * Sync 读取不能隐式推进ACK；只有客户端本地事务提交成功后才能调用本方法。
     *
     * @return array<string,mixed>
     */
    public function acknowledge(
        int $userId,
        string $authenticatedDeviceId,
        string $requestedDeviceId,
        int $lastAckEventId,
    ): array {
        if (!hash_equals(strtolower($authenticatedDeviceId), strtolower($requestedDeviceId))) {
            throw new BusinessException('IM_SYNC_DEVICE_MISMATCH', '同步设备与当前登录设备不一致', 403);
        }

        $latestEventId = (int)(AppMessageEventModel::query()
            ->where('user_id', $userId)
            ->max('event_id') ?? 0);
        if ($lastAckEventId > $latestEventId) {
            throw new BusinessException('IM_SYNC_ACK_INVALID', '确认游标不能超过当前用户最新事件', 422);
        }

        $now = time();
        $this->recordDeviceCursor($userId, strtolower($authenticatedDeviceId), $lastAckEventId, $now);

        return [
            'device_id' => strtolower($authenticatedDeviceId),
            'last_ack_event_id' => (string)$lastAckEventId,
            'server_time' => $now,
        ];
    }

    /**
     * 返回服务端仍保证可连续恢复的最小事件ID。
     */
    private function minimumEventId(): int
    {
        return (int)(AppMessageEventRetentionStateModel::query()
            ->whereKey(1)
            ->value('minimum_event_id') ?? 1);
    }

    /**
     * 单调记录设备已确认的事件位置。
     *
     * 较旧请求可能晚于较新请求到达，更新时禁止游标回退。
     *
     * @param int $userId 当前用户ID
     * @param string $deviceId 当前设备ID
     * @param int $cursor 客户端已确认游标
     * @param int $now 当前Unix秒
     * @return void
     */
    private function recordDeviceCursor(int $userId, string $deviceId, int $cursor, int $now): void
    {
        AppUserSyncStateModel::query()->insertOrIgnore([
            'user_id' => $userId,
            'device_id' => $deviceId,
            'last_ack_event_id' => $cursor,
            'last_sync_at' => $now,
            'create_time' => $now,
            'update_time' => $now,
        ]);

        AppUserSyncStateModel::query()
            ->where('user_id', $userId)
            ->where('device_id', $deviceId)
            ->update([
                'last_sync_at' => $now,
                'update_time' => $now,
            ]);

        AppUserSyncStateModel::query()
            ->where('user_id', $userId)
            ->where('device_id', $deviceId)
            ->where('last_ack_event_id', '<', $cursor)
            ->update([
                'last_ack_event_id' => $cursor,
                'update_time' => $now,
            ]);
    }

    /**
     * 转换单条用户事件为统一同步协议。
     *
     * @param AppMessageEventModel $event 用户收件箱事件
     * @return array<string,mixed>
     */
    private function eventRow(AppMessageEventModel $event): array
    {
        $eventType = $event->event_type instanceof MessageEventType
            ? $event->event_type
            : MessageEventType::from((int)$event->event_type);

        return [
            'event_id' => (string)$event->event_id,
            'event_type' => $eventType->apiName(),
            'conversation_id' => $event->conversation_id === null ? null : (string)$event->conversation_id,
            'message_id' => $event->message_id === null ? null : (string)$event->message_id,
            'notification_id' => $event->notification_id === null ? null : (string)$event->notification_id,
            'occurred_at' => (int)$event->create_time,
            // V1兼容字段；新客户端统一读取occurred_at。
            'server_time' => (int)$event->create_time,
            'payload' => $event->event_payload,
        ];
    }
}

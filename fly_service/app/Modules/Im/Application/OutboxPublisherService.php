<?php

declare(strict_types=1);

namespace app\Modules\Im\Application;

use app\enum\OutboxStatus;
use app\model\AppMessageEventOutboxModel;
use app\Modules\Im\Domain\Exception\CentrifugoPublishException;
use app\Modules\Im\Domain\Service\CentrifugoPublisher;
use Illuminate\Database\Eloquent\Builder;
use Throwable;

/**
 * IM事件Outbox发布应用服务。
 */
final class OutboxPublisherService
{
    /**
     * 注入发布能力和重试策略。
     */
    public function __construct(
        private readonly CentrifugoPublisher $publisher,
        private readonly int $batchSize,
        private readonly int $maxRetries,
        private readonly int $retryBaseSeconds,
        private readonly int $retryMaxSeconds,
        private readonly int $lockSeconds,
    ) {
    }

    /**
     * 认领并发布一批到期任务。
     *
     * 网络调用发生在数据库事务之外；短租约只解决多Worker并发认领，崩溃后允许再次发布。
     * 因此投递语义是至少一次，客户端必须按event_id幂等处理。
     *
     * @param string $workerId Worker唯一标识
     * @return array{attempted:int,published:int,retryable_failed:int,dead:int,skipped:int}
     */
    public function publishDueBatch(string $workerId): array
    {
        $now = time();
        $candidateTasks = $this->dueQuery($now)
            ->orderBy('outbox_id')
            ->limit($this->batchSize)
            ->get(['outbox_id', 'user_id', 'payload']);
        $candidateIds = $candidateTasks
            ->pluck('outbox_id')
            ->map(static fn (mixed $id): int => (int)$id)
            ->all();

        $result = [
            'attempted' => 0,
            'published' => 0,
            'retryable_failed' => 0,
            'dead' => 0,
            'skipped' => 0,
        ];

        foreach ($candidateIds as $outboxId) {
            $task = $this->claim($outboxId, $workerId, $now);
            if (!$task instanceof AppMessageEventOutboxModel) {
                continue;
            }

            ++$result['attempted'];
            try {
                $this->publisher->publish((string)$task->channel, $task->payload);
                $this->markPublished($task, $workerId, time());
                ++$result['published'];
            } catch (CentrifugoPublishException $exception) {
                $dead = $this->markFailed($task, $workerId, $exception, time());
                ++$result[$dead ? 'dead' : 'retryable_failed'];
            } catch (Throwable) {
                $exception = new CentrifugoPublishException('centrifugo_unexpected_error', true);
                $dead = $this->markFailed($task, $workerId, $exception, time());
                ++$result[$dead ? 'dead' : 'retryable_failed'];
            }
        }

        return $result;
    }

    /** 查询到期且尚未完成的用户事件投递任务。 */
    private function dueQuery(int $now): Builder
    {
        return AppMessageEventOutboxModel::query()
            ->whereIn('status', [
                OutboxStatus::Pending->value,
                OutboxStatus::FailedRetryable->value,
            ])
            ->where(static function ($query) use ($now): void {
                $query->whereNull('next_retry_at')->orWhere('next_retry_at', '<=', $now);
            })
            ->where(static function ($query) use ($now): void {
                $query->whereNull('locked_until')->orWhere('locked_until', '<=', $now);
            });
    }

    /**
     * 使用数据库条件更新原子认领单个任务。
     *
     * @param int $outboxId Outbox任务ID
     * @param string $workerId Worker唯一标识
     * @param int $now 当前Unix秒
     * @return AppMessageEventOutboxModel|null
     */
    private function claim(int $outboxId, string $workerId, int $now): ?AppMessageEventOutboxModel
    {
        $affected = $this->dueQuery($now)
            ->where('outbox_id', $outboxId)
            ->update([
                'locked_by' => $workerId,
                'locked_until' => $now + $this->lockSeconds,
                'update_time' => $now,
            ]);

        if ($affected !== 1) {
            return null;
        }

        return AppMessageEventOutboxModel::query()
            ->whereKey($outboxId)
            ->where('locked_by', $workerId)
            ->first();
    }

    /**
     * 将当前Worker持有的任务标记为发布成功。
     *
     * @param AppMessageEventOutboxModel $task Outbox任务
     * @param string $workerId Worker唯一标识
     * @param int $now 当前Unix秒
     * @return void
     */
    private function markPublished(AppMessageEventOutboxModel $task, string $workerId, int $now): void
    {
        AppMessageEventOutboxModel::query()
            ->whereKey((int)$task->outbox_id)
            ->where('locked_by', $workerId)
            ->update([
                'status' => OutboxStatus::Published->value,
                'published_at' => $now,
                'last_error' => null,
                'locked_by' => null,
                'locked_until' => null,
                'update_time' => $now,
            ]);
    }

    /**
     * 记录发布失败并计算重试或死信状态。
     *
     * @param AppMessageEventOutboxModel $task Outbox任务
     * @param string $workerId Worker唯一标识
     * @param CentrifugoPublishException $exception 脱敏发布异常
     * @param int $now 当前Unix秒
     * @return bool 是否进入死信
     */
    private function markFailed(
        AppMessageEventOutboxModel $task,
        string $workerId,
        CentrifugoPublishException $exception,
        int $now,
    ): bool {
        $retryCount = ((int)$task->retry_count) + 1;
        $dead = !$exception->retryable() || $retryCount >= $this->maxRetries;

        AppMessageEventOutboxModel::query()
            ->whereKey((int)$task->outbox_id)
            ->where('locked_by', $workerId)
            ->update([
                'status' => $dead
                    ? OutboxStatus::FailedDead->value
                    : OutboxStatus::FailedRetryable->value,
                'retry_count' => $retryCount,
                'next_retry_at' => $dead
                    ? null
                    : $now + $this->retryDelaySeconds((int)$task->outbox_id, $retryCount),
                'last_error' => $exception->safeCode(),
                'locked_by' => null,
                'locked_until' => null,
                'update_time' => $now,
            ]);

        return $dead;
    }

    /**
     * 计算带确定性抖动的指数退避秒数。
     *
     * @param int $outboxId Outbox任务ID
     * @param int $retryCount 当前失败次数
     * @return int 延迟秒数
     */
    private function retryDelaySeconds(int $outboxId, int $retryCount): int
    {
        $exponent = min(20, max(0, $retryCount - 1));
        $delay = min($this->retryMaxSeconds, $this->retryBaseSeconds * (2 ** $exponent));
        $jitterRange = max(1, min(10, $this->retryBaseSeconds));
        $jitter = abs(crc32($outboxId . ':' . $retryCount)) % ($jitterRange + 1);

        return min($this->retryMaxSeconds, $delay + $jitter);
    }
}

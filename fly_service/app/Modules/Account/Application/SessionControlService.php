<?php

declare(strict_types=1);

namespace app\Modules\Account\Application;

use app\enum\OutboxStatus;

use app\model\AppRealtimeConnectionModel;
use app\model\AppSessionControlOutboxModel;
use app\model\AppUserSessionModel;
use app\Modules\Account\Domain\Repository\RealtimeDisconnector;
use Throwable;

/** 事务外可靠投递定向断连，处理提交与 Centrifugo 完成连接建立之间的时间窗口。 */
final class SessionControlService
{
    /** 注入定向断连外部边界；共享数据库租约保证多进程可恢复认领。 */
    public function __construct(private readonly RealtimeDisconnector $disconnect)
    {
    }

    /** 处理到期任务；连续失败进入可观测死信，续期鉴权仍独立拒绝已撤销会话。 */
    public function dispatch(): array
    {
        $now = time();
        $this->recoverLegacyRevocations($now);
        $result = ['completed' => 0, 'settling' => 0, 'retried' => 0, 'dead' => 0];
        $ids = AppSessionControlOutboxModel::query()->whereIn('status', [OutboxStatus::Pending->value, OutboxStatus::FailedRetryable->value])->where('next_retry_at', '<=', $now)
            ->where(static fn($q) => $q->whereNull('locked_until')->orWhere('locked_until', '<=', $now))
            ->orderBy('next_retry_at')->limit(50)->pluck('session_id');
        foreach ($ids as $id) {
            $lease = bin2hex(random_bytes(16));
            $claimed = AppSessionControlOutboxModel::query()->whereKey($id)->whereIn('status', [OutboxStatus::Pending->value, OutboxStatus::FailedRetryable->value])
                ->where(static fn($q) => $q->whereNull('locked_until')->orWhere('locked_until', '<=', time()))
                ->update(['locked_by' => $lease, 'locked_until' => time() + 15]);
            if ($claimed !== 1) {
                continue;
            }
            $task = AppSessionControlOutboxModel::query()->whereKey($id)->firstOrFail();
            try {
                foreach (AppRealtimeConnectionModel::query()->where('session_id', $id)->where('user_id', $task->user_id)
                    ->orderBy('client_id')->cursor() as $connection) {
                    // 每次外部调用前续约；不能在持有数据库事务时等待网络。
                    $held = AppSessionControlOutboxModel::query()->whereKey($id)->where('locked_by', $lease)
                        ->update(['locked_until' => time() + 15]);
                    if ($held !== 1) {
                        continue 2;
                    }
                    $this->disconnect->disconnect($task->user_id, $connection->client_id);
                }
                // connect 回调已经登记但 Centrifugo 尚未安装连接时，第一次 disconnect 可能无目标。
                // 在两轮服务端租期及协议宽限内重复清理；旧凭证新连接始终由准入校验拒绝。
                $settled = time() >= $task->created_at + 90;
                AppSessionControlOutboxModel::query()->whereKey($id)->where('locked_by', $lease)->update([
                    'status' => $settled ? OutboxStatus::Published->value : OutboxStatus::Pending->value, 'retry_count' => 0, 'next_retry_at' => time() + 2,
                    'locked_by' => null, 'locked_until' => null, 'last_error' => null, 'updated_at' => time(),
                ]);
                ++$result[$settled ? 'completed' : 'settling'];
            } catch (Throwable) {
                $attempt = $task->retry_count + 1;
                $dead = $attempt >= 8;
                AppSessionControlOutboxModel::query()->whereKey($id)->where('locked_by', $lease)->update([
                    'status' => $dead ? OutboxStatus::FailedDead->value : OutboxStatus::FailedRetryable->value, 'retry_count' => $attempt, 'next_retry_at' => time() + min(300, 2 ** min(8, $attempt)),
                    'locked_by' => null, 'locked_until' => null, 'last_error' => 'realtime_disconnect_failed', 'updated_at' => time(),
                ]);
                ++$result[$dead ? 'dead' : 'retried'];
            }
        }
        // 只清理已越过协议宽限的连接登记，不删除登录审计或撤销事实。
        AppRealtimeConnectionModel::query()->where('expires_at', '<', time() - 120)->delete();
        return $result;
    }

    /** 兼容既有改密等批量撤销入口，从持久化撤销事实补齐可靠控制任务。 */
    private function recoverLegacyRevocations(int $now): void
    {
        $sessions = AppUserSessionModel::query()->whereIn('session_id', AppRealtimeConnectionModel::query()->select('session_id'))
            ->whereNotIn('session_id', AppSessionControlOutboxModel::query()->select('session_id'))
            ->where(static fn($q) => $q->whereNotNull('revoked_at')->orWhere('expires_at', '<=', $now))->limit(100)->get(['session_id', 'user_id']);
        foreach ($sessions as $session) {
            AppSessionControlOutboxModel::query()->insertOrIgnore(['session_id' => $session->session_id, 'user_id' => $session->user_id,
                'status' => OutboxStatus::Pending->value, 'retry_count' => 0, 'next_retry_at' => $now, 'created_at' => $now, 'updated_at' => $now]);
        }
    }
}

<?php

declare(strict_types=1);

namespace app\Modules\Account\Application;

use app\enum\OutboxStatus;

use app\exception\BusinessException;
use app\model\AppAuthAuditModel;
use app\model\AppSessionControlOutboxModel;
use app\model\AppUserSessionModel;
use app\model\AppUserSessionTokenModel;
use app\Support\Auth\AuthContext;
use app\Support\Id\IdGenerator;
use app\Support\Request\RequestContext;
use app\Support\Transaction\TransactionManager;

/** 单会话撤销的事务边界；HTTP 失效、刷新失效、审计和控制任务原子提交。 */
final class SessionRevocationService
{
    /** 注入事务；断连由提交后的控制任务处理。 */
    public function __construct(private readonly TransactionManager $transactions)
    {
    }

    /** 当前会话保护与本人归属在同一事务内判断；重复撤销仍返回同一目标标识。 */
    public function revoke(AuthContext $auth, string $target, string $ip, string $userAgent, bool $protectCurrent = true): array
    {
        return $this->transactions->run(function () use ($auth, $target, $ip, $userAgent, $protectCurrent): array {
            $now = time();
            // 两个终端互踢时统一按 UUID 加锁；锁住操作者防止已撤销的在途请求继续管理其他会话。
            $rows = AppUserSessionModel::query()->where('user_id', $auth->userId)->whereIn('session_id', [$auth->sessionId, $target])
                ->orderBy('session_id')->lockForUpdate()->get()->keyBy('session_id');
            $actor = $rows[$auth->sessionId] ?? null;
            if ($actor === null || $actor->revoked_at !== null || $actor->expires_at <= $now) {
                throw new BusinessException('AUTH_SESSION_REVOKED', '此设备已被退出，请重新登录', 401);
            }
            if ($protectCurrent && $target === $auth->sessionId) {
                throw new BusinessException('AUTH_CURRENT_SESSION_PROTECTED', '请通过设置页退出当前设备', 409);
            }
            $session = $rows[$target] ?? null;
            if ($session === null) {
                throw new BusinessException('AUTH_SESSION_NOT_FOUND', '登录会话不存在', 404);
            }
            if ($session->revoked_at === null) {
                $reason = $protectCurrent ? 'device_management' : 'logout';
                $session->fill(['revoked_at' => $now, 'revoke_reason' => $reason])->save();
                AppAuthAuditModel::query()->create([
                    'request_id' => RequestContext::requestId() ?: (new IdGenerator())->requestId(),
                    'event' => $protectCurrent ? 'session_revoked' : 'logout', 'result' => 10, 'user_id' => $auth->userId,
                    'session_id' => $target, 'device_id' => $session->device_id, 'ip' => $ip,
                    'user_agent' => mb_substr($userAgent, 0, 512), 'context' => ['actor_session_id' => $auth->sessionId], 'create_time' => $now,
                ]);
            }
            // 历史入口可能只写了会话撤销；幂等重试同样收敛其尚未过期的刷新记录。
            AppUserSessionTokenModel::query()->where('session_id', $target)->where('expires_at', '>', $now)->update(['expires_at' => $now]);
            // 即使历史会话已撤销，也补齐缺失的控制任务；唯一主键防止重复投递链。
            AppSessionControlOutboxModel::query()->insertOrIgnore([
                'session_id' => $target, 'user_id' => $auth->userId, 'status' => OutboxStatus::Pending->value, 'retry_count' => 0,
                'next_retry_at' => $now, 'created_at' => $now, 'updated_at' => $now,
            ]);
            return ['session_id' => $target];
        });
    }
}

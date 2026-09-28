<?php

declare(strict_types=1);

namespace app\process;

use app\Modules\Account\Application\SessionControlService;
use support\Container;
use support\Log;
use Workerman\Timer;
use Workerman\Worker;
use Throwable;

/** 登录会话撤销控制进程，数据库租约允许多节点恢复任务。 */
final class SessionControlWorker
{
    /** 进程启动后建立定时处理，不缓存任何请求认证状态。 */
    public function onWorkerStart(Worker $worker): void
    {
        Timer::add(0.5, function (): void {
            try {
                $result = Container::get(SessionControlService::class)->dispatch();
                if ($result['dead'] > 0) {
                    Log::error('auth.session_control.dead', $result);
                }
            } catch (Throwable) {
                Log::error('auth.session_control.unavailable', ['safe_code' => 'session_control_failed']);
            }
        });
    }
}

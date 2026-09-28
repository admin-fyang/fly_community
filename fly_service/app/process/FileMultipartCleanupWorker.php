<?php

declare(strict_types=1);

namespace app\process;

use app\Modules\File\Application\FileUploadService;
use support\Container;
use support\Log;
use Throwable;
use Workerman\Timer;
use Workerman\Worker;

/**
 * 周期取消过期S3 Multipart会话的后台进程。
 */
final class FileMultipartCleanupWorker
{
    private ?FileUploadService $uploads = null;

    /**
     * Worker启动后立即清理一次，并注册周期任务。
     */
    public function onWorkerStart(Worker $worker): void
    {
        $worker->name = '周期取消过期S3 Multipart会话的后台进程';
        $this->uploads = Container::get(FileUploadService::class);
        $this->runOnce();
        Timer::add((float)config('rustfs.multipart_cleanup_interval_seconds'), function (): void {
            $this->runOnce();
        });
    }

    /**
     * 执行一批过期会话清理并记录不含upload_id的汇总日志。
     */
    private function runOnce(): void
    {
        if (!$this->uploads instanceof FileUploadService) {
            Log::error('file.multipart.cleanup_not_initialized');
            return;
        }
        try {
            $result = $this->uploads->cleanupExpiredMultipart();
            if ($result['attempted'] > 0) {
                Log::info('file.multipart.cleanup_completed', $result);
            }
        } catch (Throwable $exception) {
            Log::error('file.multipart.cleanup_failed', ['exception_class' => $exception::class]);
        }
    }
}

<?php

declare(strict_types=1);

namespace app\process;

use app\Modules\Im\Application\OutboxPublisherService;
use PDOException;
use support\Container;
use support\Log;
use Throwable;
use Workerman\Timer;
use Workerman\Worker;

/**
 * 周期发布Centrifugo Outbox任务的常驻进程。
 */
final class CentrifugoOutboxWorker
{
    private string $workerId = '';

    private ?OutboxPublisherService $publisherService = null;

    /**
     * Worker启动后立即处理一次并注册周期轮询。
     *
     * @param Worker $worker 当前Workerman进程
     * @return void
     */
    public function onWorkerStart(Worker $worker): void
    {
        $this->publisherService = Container::get(OutboxPublisherService::class);
        $host = preg_replace('/[^A-Za-z0-9_.-]/', '_', (string)(gethostname() ?: 'host'));
        $this->workerId = substr($host . ':' . getmypid(), 0, 64);

        $this->runOnce();
        Timer::add((float)config('centrifugo.outbox_interval_seconds'), function (): void {
            $this->runOnce();
        });
    }

    /**
     * 执行一轮Outbox发布并输出不含消息正文和密钥的汇总日志。
     */
    private function runOnce(): void
    {
        if (!$this->publisherService instanceof OutboxPublisherService) {
            Log::error('centrifugo.outbox.worker_not_initialized');
            return;
        }

        try {
            $result = $this->publisherService->publishDueBatch($this->workerId);
            if ($result['attempted'] === 0) {
                return;
            }

            Log::info('centrifugo.outbox.batch_completed', $result);
            if ($result['dead'] > 0) {
                Log::warning('centrifugo.outbox.dead_letter_created', [
                    'dead_count' => $result['dead'],
                ]);
            }
        } catch (Throwable $exception) {
            Log::error(
                'centrifugo.outbox.worker_failed',
                $this->failureLogContext($exception),
            );
        }
    }

    /**
     * 构造不包含SQL、绑定参数和驱动原文的失败日志上下文。
     *
     * QueryException消息会拼入完整SQL和绑定值，不能直接写生产日志；
     * SQLSTATE与驱动错误码足以区分约束、连接、死锁等故障类型。
     *
     * @param Throwable $exception Worker本轮捕获的异常
     * @return array{
     *     exception_class:class-string<Throwable>,
     *     sql_state:string|null,
     *     driver_code:int|null,
     *     database_error:string,
     *     constraint_name:string|null,
     *     error_fingerprint:string
     * }
     */
    private function failureLogContext(Throwable $exception): array
    {
        $databaseException = $this->findDatabaseException($exception);
        $errorInfo = is_array($databaseException?->errorInfo)
            ? $databaseException->errorInfo
            : [];
        $sqlState = isset($errorInfo[0]) && is_string($errorInfo[0])
            ? $errorInfo[0]
            : null;
        $driverCode = isset($errorInfo[1]) && is_numeric($errorInfo[1])
            ? (int)$errorInfo[1]
            : null;
        $databaseError = $this->databaseErrorCode($driverCode);
        $constraintName = $this->constraintName($errorInfo[2] ?? null);

        return [
            'exception_class' => $exception::class,
            'sql_state' => $sqlState,
            'driver_code' => $driverCode,
            'database_error' => $databaseError,
            'constraint_name' => $constraintName,
            'error_fingerprint' => substr(hash(
                'sha256',
                $exception::class
                    . '|' . ($sqlState ?? '')
                    . '|' . ($driverCode ?? '')
                    . '|' . $databaseError
                    . '|' . ($constraintName ?? ''),
            ), 0, 16),
        ];
    }

    /**
     * 从异常链中查找携带PDO errorInfo的数据库异常。
     *
     * @param Throwable $exception 外层异常
     * @return PDOException|null 数据库异常，不存在时返回null
     */
    private function findDatabaseException(Throwable $exception): ?PDOException
    {
        $current = $exception;
        do {
            if ($current instanceof PDOException && is_array($current->errorInfo)) {
                return $current;
            }
            $current = $current->getPrevious();
        } while ($current instanceof Throwable);

        return null;
    }

    /**
     * 将数据库驱动错误码归类为不携带业务数据的稳定错误标识。
     *
     * @param int|null $driverCode PDO驱动错误码
     * @return string 脱敏后的稳定错误标识
     */
    private function databaseErrorCode(?int $driverCode): string
    {
        return match ($driverCode) {
            1040 => 'too_many_connections',
            1045 => 'access_denied',
            1054 => 'unknown_column',
            1146 => 'table_not_found',
            1205 => 'lock_wait_timeout',
            1213 => 'deadlock',
            1451 => 'foreign_key_parent_referenced',
            1452 => 'foreign_key_missing_parent',
            2002 => 'connection_failed',
            2006 => 'server_gone_away',
            2013 => 'connection_lost',
            3819 => 'check_constraint_violated',
            null => 'non_database_error',
            default => 'database_query_failed',
        };
    }

    /**
     * 从驱动错误中只提取由字母、数字和下划线组成的CHECK约束名。
     *
     * 驱动原文可能携带SQL值，禁止整段写日志；约束名属于数据库结构标识，
     * 可用于区分到底是哪一张表的状态约束拒绝了Worker更新。
     *
     * @param mixed $driverMessage PDO驱动错误描述
     * @return string|null 安全约束名，无法识别时返回null
     */
    private function constraintName(mixed $driverMessage): ?string
    {
        if (!is_string($driverMessage)) {
            return null;
        }
        if (preg_match(
            '/Check constraint [\'"`]([A-Za-z0-9_]{1,64})[\'"`] is violated/i',
            $driverMessage,
            $matches,
        ) !== 1) {
            return null;
        }

        return $matches[1];
    }
}

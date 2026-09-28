<?php

declare(strict_types=1);

namespace app\Infrastructure\Persistence;

use app\Support\Transaction\TransactionManager;
use Illuminate\Database\Capsule\Manager;

/**
 * Illuminate Database 事务适配器。
 */
final class IlluminateTransactionManager implements TransactionManager
{
    /**
     * 在数据库事务中执行回调，并对可重试事务异常最多重试三次。
     */
    public function run(callable $callback): mixed
    {
        return Manager::connection()->transaction($callback, 3);
    }
}

<?php

declare(strict_types=1);

namespace app\Support\Transaction;

interface TransactionManager
{
    /**
     * 在基础设施提供的数据库事务中执行回调。
     */
    public function run(callable $callback): mixed;
}

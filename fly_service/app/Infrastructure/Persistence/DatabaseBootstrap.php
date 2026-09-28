<?php

declare(strict_types=1);

namespace app\Infrastructure\Persistence;

use Illuminate\Database\Capsule\Manager;
use Webman\Bootstrap;
use Workerman\Worker;

/**
 * 为每个 Worker 初始化 Illuminate Database 连接管理器。
 */
final class DatabaseBootstrap implements Bootstrap
{
    /**
     * 为当前Worker初始化Illuminate Database全局连接解析器。
     */
    public static function start(?Worker $worker): void
    {
        $capsule = new Manager();
        $capsule->addConnection(config('database'));
        $capsule->setAsGlobal();
        $capsule->bootEloquent();
    }
}

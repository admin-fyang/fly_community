<?php

declare(strict_types=1);

namespace app\Infrastructure\Persistence;

use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Database\Capsule\Manager;
use Illuminate\Events\Dispatcher;
use Symfony\Component\VarDumper\Cloner\VarCloner;
use Symfony\Component\VarDumper\Dumper\CliDumper;
use Throwable;
use Webman\Bootstrap;
use Workerman\Worker;

/**
 * 在控制台打印执行的SQL语句
 */
final class SqlDebug implements Bootstrap
{
    /**
     * 自定义输出格式，否则输出前面会带有当前文件，无用信息
     * @param mixed $var 待输出内容
     */
    public static function dumpvar(mixed $var): void
    {
        $cloner = new VarCloner();
        $dumper = new CliDumper();
        $dumper->dump($cloner->cloneVar($var));
    }

    /**
     * 在调试模式的Worker数据库连接上注册SQL查询监听器。
     */
    public static function start(?Worker $worker): void
    {
        // Is it console environment ?
        $is_console = !$worker;
        if ($is_console) {
            // If you do not want to execute this in console, just return.
            return;
        }
        // SQL输出使用独立开关；关闭它不会影响 Log::xxx 的终端及文件输出。
        if (!config('app.sql_debug')) {
            return;
        }
        $appPath = app_path();

        $connection = Manager::connection();
        if ($connection->getEventDispatcher() === null) {
            // Capsule默认不创建事件分发器；没有它时listen会静默跳过注册。
            $connection->setEventDispatcher(new Dispatcher());
        }
        $connection->listen(function (QueryExecuted $queryExecuted) use ($appPath): void {
            try {
                if ($queryExecuted->sql === 'select 1') {
                    return;
                }

                // 绑定值可能包含密码、Token和消息内容，只输出SQL指纹及绑定数量，原始 SQL 也可能包含内联敏感值。
                $traces = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS);
                foreach ($traces as $trace) {
                    $file = $trace['file'] ?? null;
                    if (!is_string($file) || !str_contains($file, $appPath)) {
                        continue;
                    }

                    $relativeFile = str_replace(base_path(), '', $file);
                    $line = isset($trace['line']) ? (int)$trace['line'] : 0;
                    $function = isset($trace['function']) ? (string)$trace['function'] : 'unknown';
                    self::dumpvar(sprintf(
                        '[sql] [time:%s ms] [bindings:%d] [%s]',
                        (string)$queryExecuted->time,
                        count($queryExecuted->bindings),
                        hash('sha256', $queryExecuted->sql),
                    ));
                    self::dumpvar("[file] {$relativeFile}:{$line} [function]:{$function}");
                    break;
                }
            } catch (Throwable) {
                // 调试输出属于旁路能力，任何格式化或输出失败都不得中断业务查询。
            }
        });
    }

}

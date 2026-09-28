<?php
/**
 * Here is your custom functions.
 */


function getTrys(\Throwable $e,bool $trace, array $data = []) : array
{
    if ($trace) {
        $data['trace'] = $e->getTraceAsString();
    }
    return array_merge(['msg'=>$e->getMessage(),'file'=>$e->getFile(),'line'=>$e->getLine(),'code'=>$e->getCode()],$data);
}

/**
 * 递归包含指定目录下的所有 PHP 文件
 * @param string $directory 要遍历的目录路径
 */
function requireAllFiles(string $directory): RecursiveIteratorIterator
{
    // 检查目录是否存在
    if (!is_dir($directory)) {
        throw new InvalidArgumentException("目录不存在: $directory");
    }

    // 创建迭代器（跳过 . 和 .. 目录）
    $dirIterator = new RecursiveDirectoryIterator(
        $directory,
        FilesystemIterator::SKIP_DOTS | FilesystemIterator::UNIX_PATHS
    );

    // 递归迭代器
    return new RecursiveIteratorIterator($dirIterator);
    //使用示例
    /*foreach ($iterator as $file) {
        // 如果是 PHP 文件则包含
        if ($file->isFile() && $file->getExtension() === 'php') {
            require_once $file->getRealPath();
        }
    }*/
}


/**
 * 打印数组或字符串
 */
function dp(...$args): void
{
    foreach ($args as $str) {
        var_dump($str);
        echo PHP_EOL;
    }
    echo '--------' . PHP_EOL;
}

/**
 * 输出红色标题和后续调试内容。
 */
function et(string $title, mixed ...$args): void
{
    echo colorize($title, '0;31') . PHP_EOL;
    if (count($args) > 0) ec(...$args);
}

/**
 * 输出带颜色的控制台标题。
 */
function console(string $title,string $color = '31'): void
{
    echo colorize($title, "0;$color") . PHP_EOL;
}

/**
 * 输出调试参数内容。
 */
function ec(mixed ...$args): void
{
    foreach ($args as $str) {
        if (is_array($str) || is_object($str)) {
            echo var_export($str,true).PHP_EOL;
        }else{
            echo $str . PHP_EOL;
        }
    }
}


/**
 * 返回带颜色的内容
 * @param $text
 * @param $color_code
 *         0;30- 黑色
 *         0;31- 红色 ✅
 *         0;32- 绿色
 *         0;33- 黄色
 *         0;34- 蓝色
 *         0;35- 品红（洋红）
 *         0;36- 青色
 *         0;37- 白色
 *         0;90- 亮黑/灰色
 *         0;91- 亮红
 *         0;92- 亮绿
 *         0;93- 亮黄
 *         0;94- 亮蓝
 *         0;95- 亮品红
 *         0;96- 亮青
 *         0;97- 亮白
 * @return string
 */
function colorize($text, $color_code): string
{
    $escape_sequence = chr(27) . "[" . $color_code . "m";
    return  $escape_sequence . $text . chr(27) . "[0m";
}

/**
 * 打印调用栈
 * @param int $limit
 * @return void
 */
function print_call_trace(int $limit = 10) : void
{
    dp(debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS,$limit));
}


/** 返回当前请求的连接地址、解析地址及原始代理头，供地址诊断使用。 */
function ip(\support\Request $request): \support\Response
{
    return json([
        'remote_ip' => $request->getRemoteIp(),
        'real_ip' => $request->getRealIp(),

        'x_real_ip' => $request->header('x-real-ip'),
        'x_forwarded_for' => $request->header('x-forwarded-for'),
    ]);
}


/**
 * 打印执行中的sql
 * @param callable $callback
 * @param bool $isSql
 * @return void
 */
function debugSql(callable $callback,bool $isSql = true) : void
{
    // 开启
    \Illuminate\Database\Capsule\Manager::connection()->enableQueryLog();
    call_user_func($callback);

    $queries = \Illuminate\Database\Capsule\Manager::connection()->getQueryLog();
    $last = end($queries);


    if ($isSql) {
        $sql = $last['query'] ?? '';

        foreach ($last['bindings'] ?? [] as $binding) {
            $value = is_numeric($binding)
                ? (string) $binding
                : "'" . addslashes((string) $binding) . "'";

            $sql = preg_replace('/\?/', $value, $sql, 1);
        }
        var_dump($sql);
    }else{

        var_dump([
            'sql' => $last['query'] ?? null,
            'bindings' => $last['bindings'] ?? [],
            'time' => $last['time'] ?? null,
        ]);
    }



}
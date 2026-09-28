#!/usr/bin/env php
<?php

declare(strict_types=1);

use UserPurge\PurgeUser;
use UserPurge\UserPurgeRepository;
use Dotenv\Dotenv;
use Illuminate\Database\Capsule\Manager;
use app\utils\RustfsUtils;
use Predis\Client;

/**
 * 离线永久清理用户：修改下方 user_ids 后先预览，再停写并执行。
 * 数据库使用项目 .env/config/database.php；不会读取 SQL 文件中的 INSERT 数据。
 * 不启动 Webman，不连接 Redis/对象存储，不输出密码、Token 或消息内容。
 *
 * 预览
 * php bin/purge-user.php
 * 执行
 * php bin/purge-user.php --execute --offline
 */
$user_ids = ['']; // 必填：可配置多个 app_user.user_id，例如 ['123', '456']。

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
$arguments = array_slice($argv, 1);
if (in_array('--help', $arguments, true)) {
    fwrite(STDOUT, "修改脚本顶部 user_ids 后：\n  php bin/purge-user.php                         只预览\n  php bin/purge-user.php --execute --offline    停止所有写入后永久删除\n详情：docs/用户永久清理脚本.md\n");
    exit(0);
}
foreach ($arguments as $argument) {
    if (!in_array($argument, ['--execute', '--offline'], true)) {
        fwrite(STDERR, "未知参数：{$argument}\n");
        exit(1);
    }
}
$execute = in_array('--execute', $arguments, true);
if ($execute && !in_array('--offline', $arguments, true)) {
    fwrite(STDERR, "请先停止 HTTP、队列、定时任务、回调写入，再使用 --execute --offline。\n");
    exit(1);
}
if (!is_array($user_ids) || $user_ids === []) {
    fwrite(STDERR, "请先在脚本顶部配置非空 user_ids 数组。\n");
    exit(1);
}
$user_ids = array_values(array_unique(array_map('strval', $user_ids)));
foreach ($user_ids as $user_id) {
    if (!preg_match('/^[1-9][0-9]{0,18}$/D', $user_id)) {
        fwrite(STDERR, "user_ids 中存在非法正整数：{$user_id}\n");
        exit(1);
    }
}
require dirname(__DIR__) . '/vendor/autoload.php';
require __DIR__ . '/UserPurge/UserPurgeRepository.php';
require __DIR__ . '/UserPurge/PurgeUser.php';
Dotenv::createUnsafeImmutable(dirname(__DIR__))->safeLoad();
$configuration = require dirname(__DIR__) . '/config/database.php';
$rustfsConfig = require dirname(__DIR__) . '/config/rustfs.php';
$redisConfig = require dirname(__DIR__) . '/config/redis.php';
$manager = new Manager();
$manager->addConnection($configuration);
$db = $manager->getConnection();
$locked = false;
try {
    if ($db->getDriverName() !== 'mysql') {
        throw new RuntimeException('维护脚本仅支持 MySQL。');
    }
    // 该锁只防止两份清理脚本互相干扰；它不能替代停写维护。
    $lockName = 'user-purge:' . substr(hash('sha256', $db->getDatabaseName()), 0, 40);
    $locked = (int)$db->selectOne('SELECT GET_LOCK(?, 0) AS acquired', [$lockName])->acquired === 1;
    if (!$locked) {
        throw new RuntimeException('另一个用户清理脚本正在运行。');
    }
    fwrite(STDOUT, '数据库：' . $configuration['host'] . ':' . $configuration['port'] . '/' . $configuration['database'] . "\n");
    $storage = new RustfsUtils(
            $rustfsConfig['endpoint'], $rustfsConfig['public_endpoint'], $rustfsConfig['access_key'], $rustfsConfig['secret_key'],
            $rustfsConfig['bucket'], $rustfsConfig['region'], $rustfsConfig['path_style'], $rustfsConfig['ssl_verify'],
            serverEndpoint: $rustfsConfig['server_endpoint'],
    );
    $redis = new Client(['scheme'=>$redisConfig['scheme'],'host'=>$redisConfig['host'],'port'=>$redisConfig['port'],'database'=>$redisConfig['database'],'password'=>$redisConfig['password']]);
    $purger = new PurgeUser(new UserPurgeRepository($db), $storage, $redis);
    $results = [];
    foreach ($user_ids as $user_id) {
        fwrite(STDOUT, "处理 user_id={$user_id}\n");
        $results[$user_id] = $purger->run($user_id, $execute);
    }
    fwrite(STDOUT, json_encode($results, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR) . "\n");
    fwrite(STDOUT, $execute ? "全部用户清理已提交。\n" : "仅预览，未删除或修改业务数据。\n");
} catch (Throwable $exception) {
    // SQL 异常可能附带绑定的快照/凭证，禁止原样打印。
    $message = $exception instanceof \Illuminate\Database\QueryException ? '数据库操作失败；未完成的事务已回滚。请核对数据库约束及运行环境。' : $exception->getMessage();
    fwrite(STDERR, $message . "\n");
    $failed = true;
} finally {
    if ($locked) {
        $db->selectOne('SELECT RELEASE_LOCK(?) AS released', [$lockName]);
    }
}
exit(isset($failed) ? 1 : 0);

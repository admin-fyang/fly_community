#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * FlyIM 新空库安装入口：显式连接参数、空库拒绝保护、文件摘要和逐语句证据。
 * 不加载项目 .env，不自动创建/删除数据库，不升级已有结构，不创建默认账户。
 */
if (PHP_SAPI !== 'cli') {
    exit(1);
}
$options = getopt('', ['host:', 'port:', 'database:', 'username:', 'execute']);
$required = ['host', 'port', 'database', 'username'];
foreach ($required as $key) {
    if (!isset($options[$key]) || !is_string($options[$key]) || $options[$key] === '') {
        fwrite(STDERR, "用法：php bin/install-fresh.php --host=... --port=... --database=... --username=... --execute\n密码仅从 FLYIM_INSTALL_DB_PASSWORD 环境变量读取。\n");
        exit(2);
    }
}
if (!array_key_exists('execute', $options)) {
    fwrite(STDERR, "缺少 --execute，未连接数据库。\n");
    exit(2);
}
if (preg_match('/\A[A-Za-z0-9_]+\z/', $options['database']) !== 1
    || filter_var($options['port'], FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 65535]]) === false
    || preg_match('/\A[A-Za-z0-9.:-]+\z/', $options['host']) !== 1) {
    fwrite(STDERR, "连接参数格式不合法。\n");
    exit(2);
}

$base = dirname(__DIR__) . '/database/install/community';
$pdo = null;
$lockHeld = false;
$stage = 'manifest';
$created = [];
try {
    $manifest = json_decode((string)file_get_contents($base . '/manifest.json'), true, flags: JSON_THROW_ON_ERROR);
    foreach (['schema', 'seeds'] as $name) {
        $file = $base . '/' . $name . ($name === 'schema' ? '.sql' : '.json');
        if (!hash_equals($manifest[$name . '_sha256'], hash_file('sha256', $file))) {
            throw new RuntimeException('安装文件摘要不匹配：' . $name);
        }
    }
    $stage = 'connect';
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $options['host'], (int)$options['port'], $options['database']),
        $options['username'],
        (string)(getenv('FLYIM_INSTALL_DB_PASSWORD') ?: ''),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false],
    );
    $version = (string)$pdo->query('SELECT VERSION()')->fetchColumn();
    if (stripos($version, 'mariadb') !== false || version_compare($version, '8.0.16', '<') || !str_starts_with($version, '8.')) {
        throw new RuntimeException('本基线仅支持带强制 CHECK 的 MySQL 8.0.16+ / 8.x；实际版本：' . $version);
    }
    $stage = 'empty-database-guard';
    $lockName = 'flyim-install-' . substr(hash('sha256', $options['database']), 0, 40);
    $query = $pdo->prepare('SELECT GET_LOCK(?, 0)');
    $query->execute([$lockName]);
    if ((int)$query->fetchColumn() !== 1) {
        throw new RuntimeException('同一数据库已有安装过程，拒绝并行执行。');
    }
    $lockHeld = true;
    foreach (['tables' => 'table_schema', 'routines' => 'routine_schema', 'events' => 'event_schema'] as $kind => $field) {
        $query = $pdo->prepare('SELECT COUNT(*) FROM information_schema.' . $kind . ' WHERE ' . $field . ' = ?');
        $query->execute([$options['database']]);
        if ((int)$query->fetchColumn() !== 0) {
            throw new RuntimeException('数据库非空（' . $kind . '）；没有执行任何 DDL 或种子写入。');
        }
    }
    echo json_encode(['phase' => 'precheck', 'baseline' => $manifest['baseline_id'], 'database' => $options['database'], 'mysql_version' => $version, 'empty' => true], JSON_UNESCAPED_UNICODE), PHP_EOL;
    $stage = 'schema';
    $sql = (string)file_get_contents($base . '/schema.sql');
    // 此审定文件只有完整 CREATE TABLE；逐条执行并输出表名。禁止通用 SQL/历史 DROP。
    preg_match_all('/CREATE TABLE `([^`]+)`\s*\([\s\S]*?\) ENGINE[^;]*;/', $sql, $matches, PREG_SET_ORDER);
    if (count($matches) !== $manifest['table_count']) {
        throw new RuntimeException('结构语句数与基线清单不一致。');
    }
    $pdo->exec('SET SESSION FOREIGN_KEY_CHECKS=0');
    foreach ($matches as $match) {
        $pdo->exec($match[0]);
        $created[] = $match[1];
        echo json_encode(['phase' => 'table-created', 'table' => $match[1]], JSON_UNESCAPED_UNICODE), PHP_EOL;
    }
    $pdo->exec('SET SESSION FOREIGN_KEY_CHECKS=1');
    $expected = array_column($manifest['tables'], 'table');
    sort($expected);
    $actual = $pdo->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
    sort($actual);
    if ($actual !== $expected) {
        throw new RuntimeException('实际表清单与审定基线不一致。');
    }
    $stage = 'seeds';
    $seeds = json_decode((string)file_get_contents($base . '/seeds.json'), true, flags: JSON_THROW_ON_ERROR);
    // 白名单内仅权限/角色定义、关闭启动配置、注册策略及未发布空内容草稿。
    $allowed = ['app_config', 'app_content_page'];
    if (array_diff(array_keys($seeds), $allowed) !== []) {
        throw new RuntimeException('种子含未经审定的数据表。');
    }
    $pdo->beginTransaction();
    $counts = [];
    $now = time();
    foreach ($seeds as $table => $rows) {
        foreach ($rows as $row) {
            if ($table !== 'app_registration_policy') {
                $row['create_time'] = $now;
            }
            $row['update_time'] = $now;
            $columns = array_keys($row);
            foreach ($columns as $column) {
                if (preg_match('/\A[a-z_]+\z/', $column) !== 1) {
                    throw new RuntimeException('非法种子字段。');
                }
            }
            $query = $pdo->prepare('INSERT INTO `' . $table . '` (`' . implode('`,`', $columns) . '`) VALUES (' . implode(',', array_fill(0, count($columns), '?')) . ')');
            $query->execute(array_values($row));
        }
        $counts[$table] = count($rows);
    }
    $pdo->commit();
    $stage = 'complete';
    echo json_encode(['phase' => 'complete', 'baseline' => $manifest['baseline_id'], 'tables' => count($created), 'seed_counts' => $counts, 'schema_sha256' => $manifest['schema_sha256'], 'seeds_sha256' => $manifest['seeds_sha256'], 'accounts_created' => 0, 'existing_data_upgrade_supported' => false], JSON_UNESCAPED_UNICODE), PHP_EOL;
} catch (Throwable $error) {
    if ($pdo?->inTransaction()) {
        $pdo->rollBack();
    }
    // PDO 原文可能包含连接用户名/SQL 值；安装日志只保留 SQLSTATE 和驱动码。
    $detail = $error instanceof PDOException ? ['sqlstate' => $error->getCode(), 'driver_code' => $error->errorInfo[1] ?? null] : ['reason' => $error->getMessage()];
    fwrite(STDERR, json_encode(['phase' => $stage, 'status' => 'FAIL', 'created_tables' => $created, 'partial_ddl_may_remain' => count($created) > 0, 'detail' => $detail], JSON_UNESCAPED_UNICODE) . PHP_EOL);
    $failed = true;
} finally {
    if ($pdo instanceof PDO) {
        $pdo->exec('SET SESSION FOREIGN_KEY_CHECKS=1');
        if ($lockHeld) {
            $query = $pdo->prepare('SELECT RELEASE_LOCK(?)');
            $query->execute([$lockName]);
        }
    }
}
exit(isset($failed) ? 1 : 0);

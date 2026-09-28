<?php

declare(strict_types=1);

return [
    'endpoint' => getenv('RUSTFS_ENDPOINT') ?: '',
    'server_endpoint' => getenv('RUSTFS_SERVER_ENDPOINT') ?: (getenv('RUSTFS_ENDPOINT') ?: ''),
    'public_endpoint' => getenv('RUSTFS_PUBLIC_ENDPOINT') ?: '',
    'access_key' => getenv('RUSTFS_ACCESS_KEY') ?: '',
    'secret_key' => getenv('RUSTFS_SECRET_KEY') ?: '',
    'bucket' => getenv('RUSTFS_BUCKET') ?: 'chat',
    // App 安装包固定使用独立公开桶，避免与聊天文件和后台素材混存。
    // Multipart会话后台清理周期；上传会话自身固定24小时过期。
    'multipart_cleanup_interval_seconds' => 300,
    'region' => getenv('RUSTFS_REGION') ?: 'us-east-1',
    'path_style' => filter_var(getenv('RUSTFS_PATH_STYLE') ?: 'true', FILTER_VALIDATE_BOOL),
    'ssl_verify' => filter_var(getenv('RUSTFS_SSL_VERIFY') ?: 'false', FILTER_VALIDATE_BOOL),
];

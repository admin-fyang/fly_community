<?php

declare(strict_types=1);

/**
 * 客户端公开系统配置。
 *
 * 当前阶段使用静态配置验证客户端启动链路；后续管理后台上线后，由应用服务改为读取
 * app_config 已发布版本，本文件仅作为数据库不可用时的受控默认值。
 */
return [
    'app_name' => 'Fly IM',
    'logo_url' => '/favicon.ico',
    'system_version' => '1.0.0-test',
    'config_version' => 1,
    'upload_max' => 500,
    'open_upload' => 1,
    'extensions' => '',
    'mime_types' => '',
    'timezone' => 'Asia/Shanghai',
    'android_foreground_service_enabled'=>0,
    'open_add_friend'=> 1,
    'open_register' => 1,
    'phone_register_verification' => 0,
    'email_register_verification' => 0,
    'invite_register' => 0,
    'private_chat' => 1,
    'user_agreement' => '/api/v1/system/content-pages/user-agreement',
    'privacy_policy' => '/api/v1/system/content-pages/privacy-policy',
    'third_party_sdk' => '/api/v1/system/content-pages/third-party-sdk',
    'personal_information' => '/api/v1/system/content-pages/personal-information',
    'minor_privacy' => '/api/v1/system/content-pages/minor-privacy',
    'community_guidelines' => '/api/v1/system/content-pages/community-guidelines',

    /*'content_pages' => [
        ['slug' => 'user-agreement', 'title' => '用户协议', 'api_path' => '/api/v1/system/content-pages/user-agreement'],
        ['slug' => 'privacy-policy', 'title' => '隐私政策', 'api_path' => '/api/v1/system/content-pages/privacy-policy'],
        ['slug' => 'third-party-sdk', 'title' => '第三方 SDK 清单', 'api_path' => '/api/v1/system/content-pages/third-party-sdk'],
        ['slug' => 'personal-information', 'title' => '个人信息收集清单', 'api_path' => '/api/v1/system/content-pages/personal-information'],
        ['slug' => 'minor-privacy', 'title' => '未成年人隐私保护规则', 'api_path' => '/api/v1/system/content-pages/minor-privacy'],
        ['slug' => 'community-guidelines', 'title' => '社区规范', 'api_path' => '/api/v1/system/content-pages/community-guidelines'],
    ]*/
];

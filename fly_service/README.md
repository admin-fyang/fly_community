# FlyIM 社区版服务端

FlyIM 社区版是 MIT 许可的基础即时通讯服务。此目录仅保留账号、联系人、单聊、文本/图片/文件消息、基础通知和设备同步相关入口。专业版与企业版是并列的商业定位，本仓库不包含其独立功能。

## 环境

- PHP 8.5+，扩展 `json`、`intl`、`mbstring`、`openssl`、`sodium`、`pdo_mysql`
- MySQL 8.0.16+ 的 8.x 版本
- Redis；实时消息需要另行配置 Centrifugo，附件需要对象存储
- Composer

## 新库安装

1. 新建**空白**的数据库。安装器拒绝已有表、事件或存储过程的数据库，不执行升级，也不创建默认账号。
2. 运行 `composer install --no-dev`。
3. 复制 `.env.example` 为 `.env`，填写独立数据库、Redis、对象存储和认证密钥。JWT 使用 Ed25519 密钥对；私钥只放服务端。
4. 将数据库密码放入 `FLYIM_INSTALL_DB_PASSWORD` 环境变量，执行：

```bash
php bin/install-fresh.php --host=127.0.0.1 --port=3306 --database=flyim_community --username=flyim_community --execute
```

5. 运行 `php start.php start`；Windows 开发环境可运行 `php windows.php`。Web 服务默认监听 `8787` 端口。

安装结构位于 `database/install/community/`，共有 26 张表。该安装器只面向新空库；已有 FlyIM 数据需要单独规划迁移。

## 验证范围

在隔离测试库中，已验证新库安装、注册两名用户、解析单聊会话、发送文本、获取历史和事件同步。附件上传、Redis 实时链路、Centrifugo 和浏览器端完整交互尚未完成联调；公开发布前需继续核验。当前状态见上级目录的 `NOT_READY.md`。

## 许可

MIT。FlyIM 版权归 FlyIM 项目及贡献者；保留原 Webman 版权声明，详见 `LICENSE`。

# FlyIM 社区版运行环境与搭建

本文适用于本目录的 `fly_service` 服务端与 `fly_app` Flutter Web 客户端。当前代码为**待联调的社区版候选包**，已验证的范围见文末。社区版只部署基础账号、联系人和单聊能力；本文不涉及官网或其他版本。

## 1. 运行环境

| 组件           | 要求与用途                                                                                                                                     |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| PHP、Composer | `composer.json` 要求 PHP 8.4 及以上；建议使用已在本项目测试环境使用的 PHP 8.5。启用 `json`、`intl`、`mbstring`、`openssl`、`sodium`、`pdo_mysql` 扩展。Composer 用于安装服务端依赖。 |
| MySQL        | MySQL 8.0.16 及以上的 8.x 版本，使用独立的**空白数据库**。安装器不支持 MariaDB、MySQL 9 或在已有库上升级。                                                                  |
| Redis        | 用于服务端会话等运行状态；设置独立的 Redis 数据库和访问凭据。                                                                                                        |
| S3 兼容对象存储    | 图片、文件和头像上传需要预先建好存储桶。现有配置以 RustFS 命名，也可按兼容接口填写实际服务地址。浏览器必须能访问公开/签名地址及上传地址。                                                                 |
| Centrifugo   | 实时消息需要单独部署。若仅做基础 HTTP 冒烟测试，可先保持 `CENTRIFUGO_ENABLED=false`；此时不具备实时投递能力。                                                                   |
| Flutter SDK  | 用于构建 `fly_app` 的 Web 产物。项目 `pubspec.yaml` 要求 Dart `>=3.10.1 <4.0.0`；以 `flutter doctor` 和 `flutter pub get` 检查实际 SDK。                      |
| Web 服务器      | 提供 `fly_app/build/web` 静态文件，并将 API 请求转发到 PHP 服务。正式站点使用 HTTPS；WebSocket 使用 WSS。                                                            |

项目目录：

```text
fly_community/
├── fly_service/                 # PHP / Webman API、安装器和部署配置
│   └── docs/docker/centrifugo/  # Centrifugo 的 Compose 配置和部署说明
├── fly_app/                    # Flutter Web 客户端
├── FEATURES.md                 # 社区版功能范围
└── README.md                   # 本文档
```

服务端的 `app/` 是业务代码，`config/` 放运行配置，`routes/` 放接口路由，`database/install/community/` 是新库安装所用的表结构和初始数据。`docs/docker/centrifugo/` 有实时服务的 Compose 配置和[部署说明](fly_service/docs/docker/centrifugo/README.md)。客户端主要代码在 `fly_app/lib/`，静态资源在 `assets/`，Web 入口和 WASM 文件在 `web/`；构建后生成的文件在 `build/web/`。

## 2. 安装独立数据库

先在 MySQL 创建专用的空库和账号，并只授予该库所需权限。示例 SQL 中的密码需自行替换：

```sql
CREATE DATABASE flyim_community CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'flyim_community'@'%' IDENTIFIED BY '请替换为独立强密码';
GRANT ALL PRIVILEGES ON flyim_community.* TO 'flyim_community'@'%';
```

`'%'` 仅为跨主机连接示例；实际部署应限制为 API 所在主机。若 MySQL 安装在 Windows、命令运行在 WSL，`127.0.0.1` 未必指向 Windows MySQL，应填写 WSL 可访问的 Windows 主机地址。数据库名称只允许字母、数字和下划线。

进入服务端目录安装依赖：

```bash
cd fly_service
composer install --no-dev
```

安装器**不会创建数据库，也不会读取 `.env`**。先将数据库密码放入当前终端的 `FLYIM_INSTALL_DB_PASSWORD` 环境变量，再执行：

```bash
php bin/install-fresh.php --host=127.0.0.1 --port=3306 --database=flyim_community --username=flyim_community --execute
```

将 `--host`、`--port`、`--database`、`--username` 替换为实际值。密码不写在命令参数中。成功时输出 `phase=complete`、`tables=26`、`accounts_created=0`。安装器要求库内没有表、存储过程或事件；若中途失败并提示可能有部分 DDL，排查原因后应使用**新的空库**重新安装，不要在残留结构上重复执行。已有 FlyIM 数据不适用此安装流程。

## 3. 配置服务端

复制示例并编辑本地配置：

```bash
cp .env.example .env
php bin/generate-auth-keys.php
```

第二个命令会在终端打印认证密钥。将生成的值填入 `.env` 对应字段；输出含私钥和其他敏感密钥，不要写入共享日志或提交仓库。Windows 可用文件复制命令代替 `cp`。至少核对以下配置：

| 配置项                                                           | 设置要点                                                                                                                                                      |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `APP_URL`、`PUBLIC_LINK_BASE_URL`                              | 分别填写用户可访问的 API 地址和公开链接基址；本地示例为 `http://127.0.0.1:8787`。                                                                                                   |
| `DB_HOST`、`DB_PORT`、`DB_DATABASE`、`DB_USERNAME`、`DB_PASSWORD` | 指向刚安装的社区版库；勿指向现有 IM 或官网数据库。                                                                                                                               |
| `REDIS_HOST`、`REDIS_PORT`、`REDIS_PASSWORD`、`REDIS_DATABASE`   | 指向社区版可用的 Redis。                                                                                                                                           |
| `AUTH_*_KEY`、`AUTH_JWT_PRIVATE_KEY`、`AUTH_JWT_PUBLIC_KEY`     | 使用上述生成器产生的独立密钥。JWT 私钥只保存在服务端。                                                                                                                             |
| `RUSTFS_*`                                                    | 填写对象存储服务端地址、浏览器可访问地址、访问密钥、存储桶和区域；按实际证书情况设置 `RUSTFS_SSL_VERIFY`。                                                                                           |
| `CENTRIFUGO_*`、`PRESENCE_LISTENER_WS_URL`                     | 部署 Centrifugo 后，配置服务端 API 地址、浏览器 WebSocket 地址、API Key 和至少 32 字节的令牌 HMAC 密钥，再将 `CENTRIFUGO_ENABLED` 改为 `true`。浏览器通过 HTTPS 访问时，公开 WebSocket 地址应使用 `wss://`。 |

`.env.example` 中的 `AUTH_VERIFICATION_DRIVER=fixed` 和固定验证码仅供本地或隔离测试；对外提供注册前，必须接入真实的短信或邮件验证方式，并保持 `APP_DEBUG=false`、`AUTH_EXPOSE_VERIFICATION_CODE=false`。生产环境也应妥善备份密钥并限制 `.env` 的读取权限。

跨域部署时，需要在 `fly_service/config/cors.php` 的 `allowed_origins` 中加入 **Web 页面的完整来源**（协议、域名和端口）。该列表目前是静态配置，不能通过 `.env` 自动增加。对象存储也须允许 Web 来源执行实际使用的跨域上传请求。

## 4. 启动 API 与实时服务

在 `fly_service` 目录运行：

```bash
# Linux / macOS
php start.php start

# Windows 开发环境
php windows.php
```

Webman HTTP 进程监听 `0.0.0.0:8787`，对外访问时由反向代理提供 HTTPS。Redis、对象存储和 Centrifugo 是独立服务，需先启动并使其地址与 `.env` 一致。Centrifugo 的具体步骤见[部署说明](fly_service/docs/docker/centrifugo/README.md)。开启 Centrifugo 后，服务端才会启动相应的消息 Outbox 和在线状态进程；还需确认其 API Key、HMAC 密钥与 Centrifugo 自身配置一致。不要直接复用其他版本正在服务的实时频道与密钥。

## 5. 构建和部署 Web

在 `fly_app` 目录运行：

```bash
cd ../fly_app
flutter pub get
flutter build web --release \
  --dart-define=FLYIM_API_BASE_URL=https://api.example.com \
  --dart-define=PUBLIC_LINK_BASE_URL=https://chat.example.com
```

将示例地址换成社区版实际地址。若 API 与 Web 同源，可省略 `FLYIM_API_BASE_URL`，客户端默认使用当前页面来源。构建结果位于 `fly_app/build/web`；将**整个目录内容**交给 Web 服务器托管，包括 `sqlite3.wasm` 和 `sqflite_sw.js`。单页应用路由应回退到 `index.html`，同时正确提供 WASM 文件的类型。Web 本地消息库与图片缓存使用社区版独立名称。

建议由 Web 服务器将 `/api/v1/` 转发至 `127.0.0.1:8787`；若使用独立 API 域名，则按上一节配置 CORS。Centrifugo 的公开 WebSocket 地址也必须能从浏览器访问。

## 6. 核验与当前限制

1. 检查安装器输出的 `tables=26` 和 `accounts_created=0`，确认库为社区版专用库。
2. 检查 API 可访问、Web 页面能加载，浏览器开发者工具中没有 API、WebSocket、WASM 或跨域错误。
3. 使用两个新账号核验注册/登录、添加联系人、单聊文本消息、历史记录和增量同步。
4. 配好对象存储后，再核验图片/文件上传与读取；配好 Centrifugo 后，再核验两个浏览器之间的实时收发和断线重连。

目前只有新库安装、基础 HTTP 链路、Web 构建等范围完成验证；附件上传、Redis/Centrifugo 实时链路及浏览器完整交互仍待联调。**请勿将当前候选包直接作为已验收的公开部署版本。**

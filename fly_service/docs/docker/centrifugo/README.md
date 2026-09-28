# Centrifugo 部署

这里的 `docker-compose.yml` 启动一个 Centrifugo 容器，`config.json` 是它读取的配置。先装好 Docker 和 Compose，并确保 Redis 可用。下面的命令从仓库根目录执行。

## 配置

先编辑 `config.json`。仓库里的密钥、管理员密码和 Redis 连接串只是现有配置值，部署时都要换成自己的值，不要直接拿来对外运行。

- `client.token.hmac_secret_key`：连接令牌的 HMAC 密钥，至少 32 字节；与服务端 `.env` 的 `CENTRIFUGO_TOKEN_HMAC_SECRET` 相同。
- `http_api.key`：HTTP API 密钥；与 `CENTRIFUGO_API_KEY` 相同。
- `engine.redis.address`：Centrifugo 容器能访问的 Redis 地址、账号、密码和库号。当前写的是 `host.docker.internal:6379/0`；Redis 不在宿主机时，要改成实际地址。密码中有特殊字符时按 Redis URL 格式编码。
- `client.allowed_origins`：填 Web 页面的实际来源（协议、域名、端口），不要保留 `*` 用于公开站点。
- `admin.password`、`admin.secret`：如果使用管理页面，换成独立的密码和密钥；不用管理页面可关闭 `admin.enabled`。

`channel.namespaces` 已配置单聊、群聊和在线状态所用的命名空间。改动这些名称或订阅规则前，先核对服务端和客户端的频道约定。

## 启动

```bash
cd fly_service/docs/docker/centrifugo
docker compose up -d
docker compose ps
docker compose logs --tail=100 centrifugo
```

Compose 将容器的 `8000` 映射到宿主机 `8022`，供 WebSocket 和 HTTP API 使用；`9000` 映射到 `9022`，供管理页面使用。如果端口已被占用，改 Compose 左侧的宿主机端口，并同步修改下文的地址。公开部署时，建议只让反向代理访问 `8022`，不要直接暴露 API 和管理端口。

## 对接 fly_service

在 `fly_service/.env` 中填写以下配置。这里按 PHP 服务运行在同一台宿主机、浏览器通过 `chat.example.com` 访问举例；换成自己的地址。若 PHP 服务也在容器中，`127.0.0.1` 指向 PHP 容器，需使用它能访问的 Centrifugo 地址。

```dotenv
CENTRIFUGO_ENABLED=true
CENTRIFUGO_API_URL=http://127.0.0.1:8022
CENTRIFUGO_PUBLIC_WS_URL=wss://chat.example.com/connection/websocket
CENTRIFUGO_API_KEY=填写与config.json中http_api.key相同的值
CENTRIFUGO_TOKEN_HMAC_SECRET=填写与config.json中client.token.hmac_secret_key相同的值
PRESENCE_LISTENER_WS_URL=ws://127.0.0.1:8022/connection/websocket
```

反向代理需要把公开地址的 `/connection/websocket` 转发到宿主机 `8022`，并允许 WebSocket 升级。浏览器页面使用 HTTPS 时，这里必须是 `wss://`。服务端的 API URL 和在线状态监听地址走内网即可。配好后重启 `fly_service`，让消息 Outbox 和在线状态进程读取新配置。

最后用两个账号互发消息，检查接收端是否实时出现消息；断开再重连一次，确认能恢复连接。若连接失败，先看浏览器网络面板中的 WebSocket 请求，再看 `docker compose logs centrifugo` 和服务端日志；常见原因是公开地址、来源限制或两处密钥不一致。

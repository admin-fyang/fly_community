# FlyIM 社区版 Web 客户端

此目录是 FlyIM 社区版的 Flutter Web 客户端。保留账号、联系人、单聊、基础消息和设置页面。服务端位于 `../fly_service`。

## 构建

安装 Flutter SDK 后执行：

```bash
flutter pub get
flutter build web --release --dart-define=FLYIM_API_BASE_URL=https://your-api.example --dart-define=PUBLIC_LINK_BASE_URL=https://your-web.example
```

若 Web 页面与 API 位于同一来源，可省略 `FLYIM_API_BASE_URL`；公开资料链接同源时可省略 `PUBLIC_LINK_BASE_URL`。开发时请显式传入社区版 API 地址，避免连接其他环境。

社区版使用独立的浏览器本地数据库，只在首次打开时创建 12 张基础表；不会读取或迁移其他版本的本地缓存。

Web 端构建已通过；浏览器交互及附件上传仍待联调。当前状态见上级目录的 `NOT_READY.md`。

## 许可

MIT，版权归 FlyIM 项目及贡献者，详见 `LICENSE`。

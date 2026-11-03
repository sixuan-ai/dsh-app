# 历史手工部署说明

以下为旧版安装记录，不是当前推荐步骤。旧域名、frp 拓扑、DSH 启动参数可能已失效；新用户请使用 [电脑连接器](README.md)。现网旧入口在兼容期保留。

## 连接方式总览

App 的服务器地址是 `lib/main.dart` 顶部的常量 `kDefaultServerUrl`(默认 `https://dsh.ainotex.com`,即作者自己的部署)。要连你自己的 DSH 电脑,先改这个常量再打包:

```dart
const kDefaultServerUrl = 'https://dsh.example.com';  // 或局域网 http://192.168.1.5:3081
```

DSH 电脑端有一个关键限制:`dsh --profile web` **只监听 127.0.0.1,并故意拒绝 `--host 0.0.0.0`**(会把远程执行能力暴露给网络)。所以无论局域网还是公网,都需要在 dsh 前面加一层入口。两种推荐做法:

### 方式一:局域网连接(手机和电脑同一 Wi-Fi)

**方案 A(推荐,带认证)—— 用本仓库自带的认证代理:**

```sh
# 1. dsh 电脑上正常启动 web(默认 127.0.0.1:3080)
dsh --profile web

# 2. 启动认证代理,监听局域网网卡(仓库 server/dsh-auth-proxy.js,零依赖,Node ≥ 18)
LISTEN_HOST=0.0.0.0 \
LISTEN_PORT=3081 \
AUTH_USER=你的用户名 \
AUTH_PASSWORD=你的密码 \
AUTH_COOKIE_SECRET=$(openssl rand -hex 32) \
node server/dsh-auth-proxy.js
```

代理会把 Host/Origin 改写为上游地址,所以 dsh web **不需要** `--trusted-host`。

App 侧:`kDefaultServerUrl` 改为 `http://电脑局域网IP:3081`(如 `http://192.168.1.5:3081`),登录页填 `AUTH_USER` / `AUTH_PASSWORD`。HTTP 明文只在局域网内传输,且有 Basic 认证;App 已开启 `usesCleartextTraffic`。

**方案 B(无认证,仅限可信网络)—— 直接绑局域网 IP:**

```sh
dsh --profile web --host 192.168.1.5 --port 3080 --trusted-host 192.168.1.5
```

`--trusted-host` 是必须的:dsh 的浏览器信任围栏按 Host 头校验,绑非回环地址时需要显式声明。App 侧 `kDefaultServerUrl` 改为 `http://192.168.1.5:3080`,登录页用户名密码**任意填写**即可(无代理鉴权,上游不校验)。⚠️ 此方案没有任何访问控制,公共 Wi-Fi 下不要使用。

### 方式二:公网域名连接(随时随地,即作者的部署)

```
手机 App
  → https://dsh.example.com(可选 Cloudflare 代理 + 边缘压缩)
  → 公网服务器 nginx :443(Let's Encrypt 证书,WS 升级头,长超时)
  → frp tcp 隧道(加密,服务器 127.0.0.1:9980)
  → dsh 电脑 dsh-auth-proxy :3081(Basic 认证 + Host 改写)
  → dsh --profile web :3080(仅回环)
```

**dsh 电脑端配置(三步):**

1. 正常启动 web 服务:`dsh --profile web`(保持 127.0.0.1:3080,不要加任何 host 参数)。
2. 启动认证代理(同上,但 `LISTEN_HOST` 保持默认 `127.0.0.1` —— 只允许本机的 frpc 转发进来):

   ```sh
   AUTH_USER=你的用户名 AUTH_PASSWORD=你的密码 \
   AUTH_COOKIE_SECRET=$(openssl rand -hex 32) \
   node server/dsh-auth-proxy.js   # 监听 127.0.0.1:3081
   ```

   建议用 systemd / pm2 常驻。除了命令行鉴权,它还提供浏览器登录页 + HttpOnly Cookie、防爆破锁定(5 次失败锁 30 秒)、`crypto.randomUUID` polyfill。

3. frpc 穿透:参照 `server/frpc-dsh.toml.sample`,把本机 3081 映射到公网服务器的 9980 端口(`transport.useEncryption` 必须开,隧道里是 Basic 凭证明文)。

**公网服务器配置:**

- nginx:参照 `server/nginx-dsh.conf.sample`,要点是 WebSocket 升级头、`proxy_read_timeout 3600s`(流式长连接)、`client_max_body_size 200m`;证书用 `certbot --webroot` 申请,自动续期。
- frps:标准 tcp 模式,`bindPort = 7000`,token 与 frpc 一致;9980 无需对外暴露(nginx 走 127.0.0.1 回环)。
- Cloudflare(可选):域名橙云代理后自带 TLS 与 Brotli 压缩;WS 在免费套餐可用。

**App 侧:** `kDefaultServerUrl` 改为 `https://你的域名`,登录页填代理的用户名/密码。打开 `https://你的域名` 在浏览器里会先看到登录页,也可以顺便当网页版用。

### 验证部署

仓库自带协议冒烟测试,对任何部署方式都适用:

```sh
dart run tool/smoke.dart https://dsh.example.com 用户名 密码
# 检查 host.describe / session.list / session.history / 两条 WS 下行流 / 建会话-发问-取消全链路
```

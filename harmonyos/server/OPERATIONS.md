# xHarness 运维手册（链路 / 发布 / 排障）

手机 App 与 dsh 电脑之间通信链路的完整拓扑、组件位置、日常操作与故障排查。
改任何一环之前先读对应小节。

## 1. 链路拓扑

**双实例**:directory 服务按用户名路由到各自的 dsh。

```
手机 App / 浏览器
  │  HTTPS (TLS 1.2/1.3, HSTS)
  ▼
Cloudflare 边缘(*.ainotex.com, 橙云代理, SSL Full strict)
  │  APK 下载走边缘缓存(HIT 后 ~6MB/s);API/WS 回源
  ▼
HK 阿里云 nginx :443  (47.239.235.154)
  ├── dsh.ainotex.com     → frp TCP 9980 ──→ 本机 PD02: auth-proxy 3081 → dsh web 3080
  ├── mac.dsh.ainotex.com → frp vhost 8080 ─→ MacBook: 自己的认证 → dsh web
  ├── /directory/ → 127.0.0.1:3085(登录路由:用户名→子域名)
  ├── /social/    → 127.0.0.1:9981(共享社交后端,与实例无关)
  └── /releases/ /app/(集中 OTA 与官网,只在主域)
```

登录路由:`POST /directory/login {username,password}` → `{server: <子域名>}`;
用户表在 HK `/etc/dsh-directory/users.json`(`x` → 主域,`mac` → mac 子域)。

```
frp 隧道(QUIC/UDP 8000, TLS + 压缩 + 心跳 15s/90s)
  ▼
dsh 电脑(家里)
  dsh-auth-proxy 127.0.0.1:3081(Basic 认证/登录页)
  dsh web        127.0.0.1:3080(真正的 GUI/WS/API)
```

## 2. 组件清单

### 2.1 dsh 电脑(本机)

| 组件 | 位置 | 托管 |
|---|---|---|
| dsh web (3080) | 当前会话的 GUI,**绝不要重启** | 会话进程 |
| dsh-auth-proxy (3081) | `/home/x/.local/bin/dsh-auth-proxy.js` | `dsh-web-auth.service`(enabled, Restart=on-failure),env: AUTH_USER/AUTH_PASSWORD/AUTH_COOKIE_SECRET |
| frpc → HK | `/etc/frp/frpc-hk-test.toml`(dsh-web 9980 + ssh 7000) | `frpc-hk-test.service`(enabled, Restart=always) |
| frpc → qxrobot | `/etc/frp/frpc-local.toml`(ssh 9999、gupiao 9990、dsh 9980) | `frpc-local.service`(enabled, Restart=always) |
| 本地 sshd ×2(22022/22023) | `/etc/ssh/sshd_config_frpc*`,frp ssh 代理的落点 | 裸进程(尚未 systemd 化,见 §7 待办) |

### 2.2 HK 服务器 (47.239.235.154)

SSH:**仅密钥登录**(密码已禁用,密钥 = 本机 `~/.ssh/id_ed25519`):

```bash
ssh root@47.239.235.154        # 直接通,无需密码
```

| 组件 | 位置 | 托管 |
|---|---|---|
| nginx | `/etc/nginx/conf.d/dsh-ainotex.conf`(主)+ `dsh-mac.conf`(mac 实例)+ `dsh-ratelimit.conf`(限流 zone) | `nginx.service` |
| frps(8000 TCP+QUIC;9980 主 dsh 代理口;8080 vhost 供 mac 实例) | `/root/app/frpc/frps.toml` | `frps.service`(enabled, Restart=always) |
| dsh-social(9981) | `/opt/dsh-social/social-server.py`,db `/opt/dsh-social/social.db` | `dsh-social.service`(Restart=always) |
| dsh-directory(3085) | `/opt/dsh-directory/dsh-directory.py`,用户表 `/etc/dsh-directory/users.json` | `dsh-directory.service`(enabled, Restart=always) |
| 官网 | `/var/www/dsh-site/` → `/app/` | 静态 |
| OTA(认证) | `/var/www/dsh-releases/` → `/releases/`(Basic: `/etc/nginx/.htpasswd-dsh`) | 静态 |
| OTA(公开) | `/var/www/dsh-releases-public/` → `/app/dl/` | 静态 |

### 2.3 Cloudflare

- Zone: `ainotex.com`(id `6907ce0fe0754f1876e9332a82f0fcf2`),`dsh` A 记录 → 47.239.235.154,**proxied**
- SSL 模式 **Full (strict)**
- 缓存规则(ruleset `http_request_cache_settings`):`/releases/*`、`/app/dl/*` → 边缘缓存,遵循源站 TTL(APK 长缓存,JSON 清单 no-store 不缓存)

## 3. 环境变量

已写入 `~/.bashrc`(权限 600):

| 变量 | 用途 |
|---|---|
| `CF_API_TOKEN` | Cloudflare API 令牌(ainotex.com zone,Cache Rules/Zone Settings 编辑权限) |
| `CF_ZONE_AINOTEX` | ainotex.com 的 zone id,CF API 调用时引用 |

新开终端自动生效;当前终端先 `source ~/.bashrc`。

## 4. 日常操作

### 4.1 发布 App(OTA)

```bash
cd ~/code/pd02/dsh_mobile
# 1. 改代码 → flutter analyze && flutter test
# 2. pubspec.yaml 版本 +1,lib/src/changelog.dart 加条目(kAppVersion 同步)
# 3. 一键构建+上传(SSH 密钥认证,无需密码):
NOTES='本次更新摘要' tool/publish.sh
# 4. git commit && git push
```

ABI 默认 arm64-v8a(目标手机);要兼容其他架构:`ABI=all tool/publish.sh`。
旧环境回退:`SERVER_PASSWORD='...' tool/publish.sh`(走 sshpass 密码,HK 已禁用密码登录,仅对别的服务器有用)。

### 4.2 验证链路健康

```bash
# App 端全链路冒烟(HTTP RPC + 两条 WS 下行 + 建会话/发消息/取消):
cd ~/code/pd02/dsh_mobile
dart run tool/smoke.dart https://dsh.ainotex.com x '<Basic密码>'

# 快速分层定位:
curl -s -o /dev/null -w "%{http_code}\n" https://dsh.ainotex.com/app/        # CF→nginx 静态
curl -s -u 'x:<Basic密码>' -X POST https://dsh.ainotex.com/api/host.describe \
  -H 'content-type: application/json' \
  -d '{"type":"client-request","rpcId":"t","method":"host.describe","payload":{}}'
# ↑ 200 = CF→nginx→frp→auth-proxy→dsh web 全通;502 = frp/dsh 侧断;401 = 认证问题
```

### 4.3 查看/重启服务

```bash
# 本机(dsh 电脑)
systemctl status frpc-hk-test frpc-local dsh-web-auth
sudo systemctl restart frpc-hk-test        # 隧道会断 ~3s,自动重连

# HK(SSH 已免密)
ssh root@47.239.235.154 'systemctl status frps nginx dsh-social'
ssh root@47.239.235.154 'systemctl restart frps'   # 同上,瞬断自愈
ssh root@47.239.235.154 'tail -f /var/log/nginx/dsh-ainotex-error.log'
```

### 4.4 Cloudflare 操作

```bash
source ~/.bashrc   # 需要 CF_API_TOKEN / CF_ZONE_AINOTEX
AUTH="Authorization: Bearer $CF_API_TOKEN"
BASE="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_AINOTEX"

# 查看缓存规则
curl -s -H "$AUTH" "$BASE/rulesets/phases/http_request_cache_settings/entrypoint" | jq .

# 全量清缓存(发新版 APK 后不用做:APK 文件名带版本号,清单本来就不缓存)
curl -s -X POST -H "$AUTH" -H 'content-type: application/json' \
  "$BASE/purge_cache" -d '{"purge_everything":true}'

# 精确清某个 URL
curl -s -X POST -H "$AUTH" -H 'content-type: application/json' \
  "$BASE/purge_cache" -d '{"files":["https://dsh.ainotex.com/app/dl/dsh-app-latest.apk"]}'

# 查看/修改 SSL 模式
curl -s -H "$AUTH" "$BASE/settings/ssl" | jq .result.value
```

### 4.5 社交后端

```bash
ssh root@47.239.235.154 'systemctl restart dsh-social; tail -f /var/log/syslog | grep dsh-social'
# 数据库直接查:
ssh root@47.239.235.154 'sqlite3 /opt/dsh-social/social.db ".tables"'
```

## 5. 故障排查

| 症状 | 定位 |
|---|---|
| App 全白/连不上 | 按 §4.2 分层 curl;502 → 看 frpc-hk-test / frps;401 → Basic 凭证 |
| 历史加载慢 | 确认响应有 `content-encoding: gzip`(nginx gzip_types 生效);隧道压缩在 frpc-hk-test.toml 的 dsh 代理上 |
| OTA 下载慢 | `curl -sI <apk-url> \| grep -i cf-cache-status`,HIT 才走边缘;MISS 多 → CF 缓存规则 |
| APK 更新检测不到新版本 | 清单必须 no-store:`curl -sI .../latest.json \| grep -i cache-control`;versionCode 以 aapt 读数为准(publish.sh 已处理 split-per-abi +2000 偏移) |
| SSH "Connection closed" | HK 已是密钥登录;若换机器,先把该机器公钥加进 `/root/.ssh/authorized_keys` |
| WS 掉线频繁 | App 端 20s ping 保活,nginx 3600s 读超时已配;仍掉 → 看 frp 心跳日志 |
| frp 隧道断了 | `systemctl status frpc-hk-test`(本机)与 `frps`(HK),两者 Restart=always 会自愈;持续失败看 token 是否一致 |

## 6. 安全基线(已实施)

- 全站强制 HTTPS(80 → 301),HSTS,X-Frame-Options DENY,nosniff
- `/social/`、`/releases/` 限流 5r/s(burst 20)防 Basic 爆破;`/api/` 20r/s(burst 60)
- HK SSH 仅密钥;frp 隧道 TLS + 加密;社交服务 JSON 体上限 768KB
- CF SSL Full (strict)(边缘→源站证书校验)

**仍建议轮换的凭证**(都曾出现在聊天记录):
1. Basic 密码(`x` 用户,`/etc/nginx/.htpasswd-dsh` + auth-proxy 的 AUTH_USER/AUTH_PASSWORD)——轮换后手机和浏览器需重新登录
2. frp token(HK frps.toml + 本机两个 frpc.toml)
3. auth-proxy 的 AUTH_COOKIE_SECRET(轮换 = 所有浏览器登录态失效)
4. HK root 密码(虽已禁密码登录,建议仍改)
5. CF API 令牌(在 CF 控制台 revoke 后重签,更新 `~/.bashrc`)

## 7. 待办/已知项

- 本机两个隧道用 sshd(22022/22023,`/etc/ssh/sshd_config_frpc*`)仍是裸进程,可照 frpc 模式 systemd 化
- auth-proxy 是 Restart=on-failure(崩溃才重启),够用;想更稳可改 always
- App 已接 directory 登录(v1.9.0):登录页用户名 → `/directory/login` 路由到对应实例,实例 URL 存 `serverUrl` 偏好,启动直连;`/social/`、OTA 清单、头像固定主域。**注意**:mac 用户在 `/social/` 会 401(htpasswd 只有 x),社交多用户化未做
- 新增实例 = users.json 加用户 + 新 vhost + 证书 + frp 隧道;Mac 侧 dsh web 未运行时其 auth 代理会回 "upstream error"(正常,唤醒 Mac 即可)
- iOS 端:MacBook Air 可构建,TestFlight 先行;OTA 代码路径已按平台门控到 Android

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
| ↑ dsh 自身会话 cookie 代理 | 同上,opt-in: `DSH_TOKEN_FILE` 指向 dsh web 日志 | 由 `dsh-web-auth.service` 的 env 打开,见 §2.1.1 |
| frpc → HK | `/etc/frp/frpc-hk-test.toml`(dsh-web 9980 + ssh 7000) | `frpc-hk-test.service`(enabled, Restart=always) |
| frpc → qxrobot | `/etc/frp/frpc-local.toml`(ssh 9999、gupiao 9990、dsh 9980) | `frpc-local.service`(enabled, Restart=always) |
| 本地 sshd ×2(22022/22023) | `/etc/ssh/sshd_config_frpc*`,frp ssh 代理的落点 | 裸进程(尚未 systemd 化,见 §7 待办) |

#### 2.1.1 dsh 自身会话 cookie 代理(opt-in)

dsh web 除了本代理的 Basic 门禁之外,还有**自己的一道门**:每个 `/api` 请求和
WebSocket 升级都必须带 `dsh-auth-<authority>` cookie,该 cookie 由启动时打印的
`?token=` 换取。

- 这个 token 是**每个进程随机生成**的(源码 `processLaunchToken()`),所以
  `dsh web` 每次重启都会变,**客户端无法长期保存**——手机里存的 token 会立刻失效。
- 但 cookie 的**签名密钥是持久化的**(凭据库 `client-connection/browser-session`),
  所以**已换到的 cookie 能跨重启继续用**(30 天有效)。

因此代理可以直接替客户端完成换取并缓存:

| 环境变量 | 作用 |
|---|---|
| `DSH_TOKEN_FILE` | `dsh web` 启动日志路径。**设置即启用**该功能;不设则完全保持原样 |
| `DSH_COOKIE_CACHE` | cookie 落盘路径(默认 `dsh-session-cookie`,权限 600) |
| `DSH_COOKIE_REFRESH_MS` | 后台刷新间隔,默认 12 小时 |

启用后客户端**只需 Basic 账号密码**,不再需要 token,也不受 `dsh web` 重启影响。
上游若返回 401(凭据库被轮换),代理会丢弃旧 cookie 并立即重新换取。

注意:代理会读取 `DSH_TOKEN_FILE` 指向的日志,该文件含 token,权限应保持 600。

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

## 8. 2026-11-02 迁往广州节点（当前默认入口）

App 的默认服务器、OTA 清单、AI 内容源、官网下载链接都已从香港迁到广州，
`dsh.ainotex.com` 旧入口下线。

```
手机 App
  │ HTTPS
  ▼
广州腾讯云 nginx (123.207.241.42, dsh.sixuanai.com)
  ├── /directory/        → 127.0.0.1:3085  账号目录（users.json + backends.json）
  ├── /_dsh_auth         → 目录内部校验，返回该设备的内部凭据
  ├── /                 → Tailscale → x-OMEN 100.89.0.1:3081 认证代理 → dsh web 18395
  ├── /social/          → 127.0.0.1:9981   社区/好友/私聊（数据自 HK 迁入）
  ├── /releases/        → /var/www/dsh-releases        账号校验的 OTA 通道
  ├── /releases-public/ → /var/www/dsh-releases-public 免认证下载副本（官网用）
  └── /app/content/     → /var/www/dsh-content         AI 日报/知识学习 JSON（公开）
```

组件位置（广州）：`dsh-directory.service`（`/opt/dsh-directory`）、
`dsh-social.service`（`/opt/dsh-social`，库文件 `social.db` 由 HK
`sqlite3.backup()` 在线热备迁来，社交 token 原样保留）、nginx 站点文件
`/etc/nginx/sites-available/dsh-sixuanai`、证书 `dsh.sixuanai.com`。

**香港现状**：`dsh.ainotex.com` 的 vhost 已移出 `conf.d`，原文件备份在
`/root/nginx-backup-20261102/dsh-ainotex.conf.removed`；同目录新增
`dsh-ainotex-tombstone.conf` 统一返回 404。

2026-11-02 同步清理：`dsh-register.service`（3086）与 `dsh-social.service`（9981）
在旧入口下线后已无消费者，已停用并删除单元与目录，归档在
`/root/backup-20261102/dsh-register-social.tgz`；本机侧专门为 HK 服务的
`dsh-omen-tunnel.service` 也已停用移除（备份在
`~/.config/systemd/user/backup-20261102/`），HK 的 9982 端口随之消失。

同日继续清理：`dsh-computers.conf`（`omen.`/`x26.`）、`dsh-mac.conf`、
`dsh-ratelimit.conf`（zone 已无使用者）、directory(3085) 及其单元与
`/etc/dsh-directory` 全部移除；`conf.d` 里 8 个 `.bak-*` 与 2 个
`.before-mars-*` 历史备份也一并挪走。10 个 vhost 备份与
`dsh-directory-etc.tgz`（含 users.json，600）都在
`/root/backup-20261102/`。香港现在只剩 nginx + frps（供 linkr 等非 DSH
项目）与各公司站 vhost；社交数据以广州 `/opt/dsh-social/social.db` 为准。

`ainotex.com` 旧品牌域名同日退役：主域、`www`、`me`、`study`、`git` 的 vhost
（上游 `10.100.100.2:80` 早已不可达）全部换成 `dsh-ainotex-tombstone.conf`
之外的 `ainotex-tombstone.conf` 墓碑，统一 404；`dsh.ainotex.com` 仍由独立墓碑
处理。**该域名下只剩 `ota.ainotex.com`**（硬件 BOX / Mars OTA，`ota-ainotex.conf`）。
`linkr.ainotex.com` 中继随后确认不再需要，vhost 已删除，其证书一并删除。

两个墓碑改为 `return 404`（80）+ `ssl_reject_handshake on`（443），不再引用任何
证书，因此 certbot 只为 `ota.ainotex.com` 与 `qxrobot.com`（DNS-01）两个有效证书
续期；退役域名的 10 份证书/续期配置已用 `certbot delete` 清除。已退役的 vhost
与证书备份痕迹都在 `/root/backup-20261102/`。

**香港 DNS**：2026-11-02 发现其 VPC DNS（`100.100.2.136/138`）不再应答，导致
所有按名出站（certbot 续期、访问 GitHub / dsh.sixuanai.com）超时。已新增
`/etc/systemd/resolved.conf.d/99-public-dns.conf`，改用 `223.5.5.5`/`119.29.29.29`
优先、VPC DNS 兜底。香港无 IPv6 出口（ACME 走 IPv4 正常）。

恢复旧入口：删除墓碑文件，把备份的 `dsh-ainotex.conf.removed` 还原成
`/etc/nginx/conf.d/dsh-ainotex.conf`，`nginx -t && systemctl reload nginx`。


## 局域网与公网目录账号兼容

2026-11-03 实测：公网目录账号与本机认证代理内部账号是两套凭据。公网 nginx 经过目录验证后换用内部凭据，手机直接连接 `http://电脑局域网IP:3081` 时不会发生该转换，可能在 WebSocket 握手收到 401，即使电脑 DSH 正常、手机公网连接也正常。

认证代理现可选读取 `AUTH_USERS_FILE`，在原 `AUTH_USER` / `AUTH_PASSWORD` 及 Cookie 校验之外接受额外本地密码散列。文件只读、缺失或格式不合法时拒绝额外账号，原内部账号仍可用。当前本机路径 `/home/x/.dsh/auth/lan-users.json`，权限 0600，systemd drop-in 位于 `~/.config/systemd/user/dsh-web-auth.service.d/lan-users.conf`。文件及凭据不得提交仓库。

散列文件结构为 `version:1`、`users` 数组，每项为 `username`、`algorithm:"pbkdf2-sha256"`、16 字节十六进制 `salt`、32 字节十六进制 `digest`、`iterations`；当前使用 210000 次，验证器限制在 100000 至 1000000 之间。须由管理员确认账号已绑定本机后再登记，不能批量导入目录中的其他账号。运行时仅本地验证，不依赖公网；目录账号改密、解绑或撤销后，也要同步更新或删除本地散列。它不是自动目录同步功能。

本轮登记前，使用手机正在发送的账号向既有 HTTPS 目录认证，确认 `OMEN 笔记本` 与 `dsh.sixuanai.com` 绑定后生成散列；临时明文材料已删除，未改旧内部账号、未关闭认证、未开放原始 DSH 端口。

回退额外账号支持：移除该 drop-in 的 `AUTH_USERS_FILE` 配置，`systemctl --user daemon-reload` 后重启 `dsh-web-auth`；保留原账号及 Cookie Secret，不需要重启 DSH。散列文件独立保管，删除其中某个账号即可撤销其通过新 Basic 请求的访问。既有 Cookie 会话具有独立有效期，立即撤销 Cookie 需另行轮换 Cookie Secret 并考虑全部客户端重登。

隔离回归测试：`node server/tests/dsh-auth-proxy-auth.cjs`。测试使用临时合成凭据与本机假上游，不读真实凭据。

## xHarness 电脑连接器（2026-11-03）

新增设备配对链路，旧 3081 与网站根路径继续兼容。安装与回退见 [连接器维护文档](../docs/connector/README.md)，已执行检查与范围见 [验收记录](../docs/connector/IMPLEMENTATION.md)。

本机新服务为 `xharness-connector`（TLS 3082）和 `xharness-auth-bridge`（仅回环 3083），复用现有回环 18395 DSH；配置/设备散列位于用户私有目录 `~/.local/share/xharness-connector`，不能提交。电脑应用菜单新增管理入口。新手机配对需要 App 2.2.0+137；不会静默把手机原账户切到新设备凭据。

广州现网新增 `xharness-hub`（回环 3087）以及 `xharness-accounts` 导出 service/path/timer。nginx 在 `dsh-sixuanai` 的 HTTPS vhost 增加 `/etc/nginx/snippets/xharness-connector.conf` include，仅处理 `/connector/`。修改前备份保存在该 vhost 同目录的 `.xharness-backup-时间` 文件。hub 使用独立服务用户，仅能读取 `/var/lib/xharness-accounts/accounts.json` 的加盐散列，原 `/etc/dsh-directory/users.json` 的 root:root 0600 权限保持不变。

Tailscale 将网关连接到电脑，新链路限定连接器端口并固定证书。当前电脑已用现有绑定账户登记，生产环境未启用 `CONNECTOR_TEST_LOOPBACK`。检测现有设备、撤销设备、检查公网状态均不需要把长期账号密码写进手机配对码。


### x-26 第二台电脑安装

2026-11-03 在 x-26 用户 x 下新增连接器，复用原 `dsh-web.service`（回环 3080）。该服务只把启动授权信息写入用户 journal，因此连接器新增 `--token-unit dsh-web.service` 接入方式；原服务 PID 2963644 未改变。独立网关 TLS 3082、认证桥回环 3083 均 active，TLS 与公网身份检查通过。局域网地址当前为 172.16.3.193，Tailscale 为 100.89.0.2。

x-26 已作为独立节点登记到同一个现有账户的连接器 registry，未把仅接受设备凭据的新路由混入旧目录账户列表。真实 Tailscale 直连与公网 HTTP/WS 检查均读到相同的 165 个会话。临时测试设备配对成功后已撤销。手机本身的首次确认仍由手机 App 完成；现有 2.2.0 二维码首次领取要求手机与 x-26 局域网互通，不能把服务安装完成当作手机已经绑定。

### App 2.2.1 多电脑

配对电脑改为手机安全存储中的多条记录，旧 x-26 单条配对兼容迁移。连接中心同时保留原账号电脑（OMEN）与已配对电脑（x-26）。未修改两台电脑的 DSH、网关身份或实际手机设备记录。真实客户端状态切换已验证 x-26 → 原 OMEN 账号 → 配对 OMEN → x-26，审计用测试设备与临时凭据已清理。

## 2026-11-03：Cloudflare R2 公共安装包加速

公共签名 APK 使用 `xharness-releases` R2 桶和 `downloads.ainotex.com` 自定义域名。原 `dsh.sixuanai.com/releases-public/` 入口对已验证版本返回 302，更新清单仍 no-store。发布器自动上传、校验、更新映射并平滑 reload；原安装包保留，`?origin=1` 可取源站备用副本。业务认证与 DSH/WebSocket 路由未改动。

部署、凭据配置、回滚和测速见 [Cloudflare 下载运维](../docs/releases/CLOUDFLARE_DOWNLOADS.md)。

# DSH 账号注册服务（邮箱验证码）

给用户开通一个**登录账号**：他用**自己的任意邮箱**（Gmail / QQ / 公司邮箱都可以）
收验证码、自设密码，之后即可在 App 里用邮箱（或系统派生的用户名）登录。

> 邮箱在这里的作用是**证明他确实拥有该邮箱**，不要求是公司域名。默认不做域名
> 限制；只有当你只想放行特定域名时，才设置 `REGISTER_ALLOWED_DOMAINS`。

> ⚠️ **注册 ≠ 能连上电脑。** 验证通过只是写一条登录记录，**不会**创建 DSH 实例
> （子域名 / 证书 / frp 隧道）。用户还要在自己电脑上装好 DSH 并配好隧道，由
> 管理员补上 `subdomain` 之后才真正可用。页面与登录错误都会明确说明这点。

## 组成

| 文件 | 作用 |
|---|---|
| `dsh-register.py` | 注册服务：发码、校验、建账号（127.0.0.1:3086） |
| `dsh-directory.py` | 登录路由：用户名/邮箱 → 实例子域名（127.0.0.1:3085，替换原版） |
| `dsh-register.service` | systemd 单元 |
| `nginx-register.snippet.conf` | nginx 反代片段（必须排在现有 `/directory/` 之前生效） |

两个脚本都**零依赖**（python3 标准库 + sqlite3），与本仓库 `social-server.py`
风格一致。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/directory/register/config` | 返回允许域名、密码长度、是否已配发信 |
| POST | `/directory/register/request` | `{email}` → 发送验证码（任意邮箱） |
| POST | `/directory/register/verify` | `{email, code, password}` → 创建账号 |
| POST | `/directory/login` | `{username, password}` → 实例地址，username 可用邮箱 |

`/directory/login` 的新错误码：`not-provisioned`（403）表示**密码正确但实例未
开通**，App 据此提示联系管理员，而不是误报「密码错误」。

## 部署

```bash
# 1) 代码
sudo mkdir -p /opt/dsh-register
sudo cp dsh-register.py /opt/dsh-register/
sudo cp dsh-directory.py /opt/dsh-directory/dsh-directory.py   # 替换登录服务

# 2) 配置（权限 600：里面有邮箱密码）
sudo mkdir -p /etc/dsh-register
sudo tee /etc/dsh-register/register.env >/dev/null <<'EOF'
REGISTER_ALLOWED_DOMAINS=yourcompany.com
SMTP_HOST=smtp.exmail.qq.com
SMTP_PORT=465
SMTP_USER=noreply@yourcompany.com
SMTP_PASSWORD=在此填客户端专用密码
SMTP_FROM_NAME=DSH
EOF
sudo chmod 600 /etc/dsh-register/register.env

# 3) 服务
sudo cp dsh-register.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dsh-register

# 4) nginx（把片段里的 location 拷进 dsh-ainotex.conf 的 443 server 块）
sudo nginx -t && sudo systemctl reload nginx
```

### 腾讯企业邮箱

- **`SMTP_PASSWORD` 必须是「客户端专用密码」**，不是邮箱登录密码。
  在 邮箱设置 → 客户端专用密码 里生成。
- 服务器 `smtp.exmail.qq.com`，SSL 端口 `465`（默认值已对）。
- 若用 `587`，服务会自动走 STARTTLS。

### 不配 SMTP 也能先跑通

未设置 `SMTP_USER`/`SMTP_PASSWORD` 时进入**演练模式**：不发信，验证码写进
`journalctl -u dsh-register` 日志，`/config` 的 `mailEnabled` 返回 `false`，
App 会提示「验证码请向管理员索取」。适合先把流程和 UI 验证完再接入真发信。

## 配置项

| 变量 | 默认 | 说明 |
|---|---|---|
| `REGISTER_APP_TOKEN` | 空 | App 调用注册接口时携带的共享凭据（请求头 `x-dsh-app`）。**设置后公网匿名调用一律 401**；留空则不做校验 |
| `REGISTER_ALLOWED_DOMAINS` | 空 | 逗号分隔的允许域名。**空 = 接受任意邮箱（默认，符合"用户用自己邮箱注册"）**；仅在需要限制范围时才设置 |
| `REGISTER_DEFAULT_SUBDOMAIN` | 空 | 新账号默认实例域名。留空则账号建好但标记为未开通 |
| `REGISTER_CODE_TTL` | 600 | 验证码有效期（秒） |
| `REGISTER_SEND_COOLDOWN` | 60 | 同一邮箱重发间隔（秒） |
| `REGISTER_IP_HOURLY_LIMIT` | 10 | 同 IP 每小时发码上限 |
| `REGISTER_MAX_ATTEMPTS` | 5 | 单个验证码最多试错次数 |
| `REGISTER_DB_PATH` | `/opt/dsh-register/register.db` | 账号/发码记录 |
| `DIRECTORY_USERS_FILE` | `/etc/dsh-directory/users.json` | 登录用户表 |

## 防公网滥用（App 凭据）

注册接口经 nginx 暴露在公网，而注册者本身还没有账号，所以**不能**用用户身份
鉴权。为防止路径被扫到后被反复触发发信（消耗邮箱配额），接口要求请求头
`x-dsh-app` 携带一个**随 App 分发的共享凭据**：

```
x-dsh-app: <REGISTER_APP_TOKEN>
```

它在 App 里由 `kRegisterAppToken` 提供（可用 `--dart-define=DSH_REGISTER_APP_TOKEN=...`
覆盖）。这挡的是**随手扫描**，不是身份认证，因此是共享值而非每用户凭据。

实测（生产）：

| 调用方式 | 结果 |
|---|---|
| 匿名 `curl` 请求验证码 | `401 app-unauthorized` |
| 匿名读 `config` | `401 app-unauthorized` |
| 带 App 头 | 正常 |

留空 `REGISTER_APP_TOKEN` 则完全关闭该校验（保持原行为）。

## 安全设计

- **邮箱格式校验**：正则校验，拒绝格式非法的地址。默认不限制域名（用户可用
  自己的邮箱）；若设置了 `REGISTER_ALLOWED_DOMAINS` 则只放行名单内域名，
  且**不区分**「格式错」与「域名不允许」，避免通过错误信息探测策略。
- **验证码**：6 位数字，`scrypt`/`sha256` 加盐后存库，不存明文；`TTL` 过期、
  试错超限即作废、**用后即删**。
- **限流**：同邮箱 60 秒冷却 + 同 IP 每小时上限 + nginx 层 5r/s。
- **密码**：`hashlib.scrypt`（n=2^14）加盐存 sqlite；`users.json` 里按登录服务
  的要求保留明文（与原 `x`/`mac` 一致，文件权限 600）。
- **防枚举**：请求验证码时不透露该邮箱是否已注册。
- `users.json` 写入用**临时文件 + 原子替换**，避免崩溃截断登录表。

## 开通实例（注册之后）

账号建好后，管理员为其开通实例：

1. 对方电脑装好 DSH 并配好 frp 隧道（见 `server/OPERATIONS.md`）；
2. 在 `/etc/dsh-directory/users.json` 对应记录上补 `subdomain`；
3. 配 vhost + 证书（文档中「新增实例」一节）。

之后该账号登录就会返回实例地址，App 正常连接。

## 一个账号，多台电脑

`dsh-directory.py` 支持一个账号挂多台电脑。把记录改成带 `computers` 数组：

```json
"x": {
  "password": "...",
  "email": "sixuan@ainotex.com",
  "computers": [
    { "id": "omen", "name": "OMEN 笔记本", "subdomain": "dsh.ainotex.com",
      "default": true },
    { "id": "mac",  "name": "MacBook",     "subdomain": "mac.dsh.ainotex.com" }
  ]
}
```

- `subdomain` 留空的项**不会**出现在列表里（实例未开通，自动省略）。
- 老格式（顶层 `subdomain`，无 `computers`）等价于只有一台，继续可用，不用改。

**接口**：

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/directory/login` | 返回该账号**所有**已开通电脑 + 兼容字段 `server`（= 默认那台） |
| POST | `/directory/resolve` | 按 `computerId` 返回其中一台的具体实例地址 |

App 登录后会保存电脑列表，在「连接与安全」里显示，随时从一台切到另一台；
切换后连接的是新电脑的实例，会话列表也随之换成那台的。

## 已知限制

- 尚无「忘记密码」流程；需管理员在 `users.json` 改密码或让其重新注册
  （同邮箱重新验证会**覆盖**密码并复用原用户名）。
- 未做邮箱格式的 MX 校验，只做正则 + 域名白名单。
- 注册接口不要求 Basic 认证（新用户没有凭据），因此**限流是主要防线**；
  若要更强防护，可在 nginx 上加 CAPTCHA 或 IP 白名单。

## 双电脑账号接入（2026-09-12）

注册账号 `2051044997` 已绑定两台电脑：

| 电脑 ID | 名称 | App 访问入口 | 网关上游 |
|---|---|---|---|
| `omen`（默认） | 本机 · OMEN | `https://omen.ainotex.com` | HK `127.0.0.1:9982` → SSH 加密隧道 → 本机 `127.0.0.1:3081` |
| `x26` | 远程电脑 · x-26 | `https://x26.ainotex.com` | HK `127.0.0.1:9980` → 现有 frp 加密隧道 → x-26 `127.0.0.1:3081` |

`x-26` 是 SSH `47.239.235.154:7000` 背后的电脑，**不是**直接 SSH 到
`47.239.235.154:22` 的 HK 网关。旧 `dsh.ainotex.com` 仍保留原入口。

### 统一账号认证

- 新电脑域名的 nginx 用内部 `auth_request` 调用目录服务 `GET /internal/auth`。
- 邮箱/用户名、密码均从 `users.json` 实时核验，并检查目标域名属于该账号的
  `computers`。其他账号不能因为知道域名而访问电脑。
- `/etc/dsh-directory/backends.json`（600）保存两个电脑端代理的内部凭据，
  格式为 `{ "电脑域名": { "username": "…", "password": "…" } }`。
  目录服务将其交给 nginx 转发；**不返回给 App，也不提交到仓库**。
- `X-DSH-Target` 必须由 nginx 固定设置；`/_dsh_auth` 必须为 `internal`，
  `/internal/auth` 不得另行暴露公网。目录服务保持监听回环地址。
- 新网关不接收客户端 cookie 作为账号认证，也不向客户端发送内部代理 cookie。
  HTTP 和 WebSocket 握手都必须校验账号。
- 主域 `/social/` 和 `/releases/` 同样使用账号认证（`@shared` 范围），
  已开通账号可以访问；旧 directory 账号继续可用。
- 重新验证邮箱改密码会保留 `computers`、`subdomain` 和原始创建时间；
  新密码立即用于后续 HTTP 请求及 WebSocket 握手。已建立的 WebSocket 不主动断开。

### 常驻与运维

- 本机用户服务：`~/.config/systemd/user/dsh-omen-tunnel.service`，已 enable，
  用户 lingering 已开启。SSH 反向端口只绑定 HK 回环地址，断线自动重连。
- HK 新 nginx 配置：`/etc/nginx/conf.d/dsh-computers.conf`。
- 两域证书：`/etc/letsencrypt/live/dsh-computers/`，certbot 自动续期。
- 本次原始文件备份：HK `/root/dsh-connect-backup-20260912/`（含敏感账号表，勿分发）。
- 未重启两台电脑的 DSH 进程；只重启了 HK 注册/目录服务并 reload nginx。

### App v1.35.7

登录页只保留邮箱/用户名、密码和注册入口，登录后自动连接默认电脑。
在“连接与安全”中选择电脑；切换结果保存到本机，重开 App 恢复上次电脑。
聊天缓存按账号和服务器分别存储，旧通用缓存文件保留，但不混入新电脑记录。

### 验证

```bash
python3 -m unittest discover -s server/registration -p 'test_*.py' -v
```

`tool/check_account.dart` 通过 stdin 接收 `{ "username": "…", "password": "…" }`，
只读验证目录登录、两台电脑 resolve、实时 WebSocket ready 和 HTTP 会话列表。
勿把密码放到命令参数、命令历史或日志中。

本次协议验收：两台电脑均通过 WebSocket ready 和 HTTP 会话列表读取；源站匿名/错密码返回 401，未绑定账号返回 403，内部鉴权路径公网返回 404。App 测试 213 项、服务端回归测试 3 项通过。

手机已安装 v1.35.7（versionCode 2128），实测 OMEN → x-26 切换成功；App 过滤子代理后，x-26 列表显示 94 个会话（协议原始列表 153 个）。公开 APK 下载 SHA-256 与发布清单一致；Cloudflare 的 latest APK/清单缓存已刷新。

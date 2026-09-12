# DSH 账号注册服务（企业邮箱验证码）

给同事开通一个**登录账号**：他用公司邮箱收验证码、自设密码，之后即可在 App
里用邮箱（或系统派生的用户名）登录。

> ⚠️ **注册 ≠ 能连上电脑。** 验证通过只是写一条登录记录，**不会**创建 DSH 实例
> （子域名 / 证书 / frp 隧道）。同事还要在自己电脑上装好 DSH 并配好隧道，由
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
| POST | `/directory/register/request` | `{email}` → 发送验证码 |
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
| `REGISTER_ALLOWED_DOMAINS` | 空 | 逗号分隔的公司域名。**空 = 接受任意邮箱**，生产务必设置 |
| `REGISTER_DEFAULT_SUBDOMAIN` | 空 | 新账号默认实例域名。留空则账号建好但标记为未开通 |
| `REGISTER_CODE_TTL` | 600 | 验证码有效期（秒） |
| `REGISTER_SEND_COOLDOWN` | 60 | 同一邮箱重发间隔（秒） |
| `REGISTER_IP_HOURLY_LIMIT` | 10 | 同 IP 每小时发码上限 |
| `REGISTER_MAX_ATTEMPTS` | 5 | 单个验证码最多试错次数 |
| `REGISTER_DB_PATH` | `/opt/dsh-register/register.db` | 账号/发码记录 |
| `DIRECTORY_USERS_FILE` | `/etc/dsh-directory/users.json` | 登录用户表 |

## 安全设计

- **域名白名单**：非公司域名直接拒绝，且**不区分**「格式错」与「域名不允许」，
  避免通过错误信息探测策略。
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

## 已知限制

- 尚无「忘记密码」流程；需管理员在 `users.json` 改密码或让其重新注册
  （同邮箱重新验证会**覆盖**密码并复用原用户名）。
- 未做邮箱格式的 MX 校验，只做正则 + 域名白名单。
- 注册接口不要求 Basic 认证（新用户没有凭据），因此**限流是主要防线**；
  若要更强防护，可在 nginx 上加 CAPTCHA 或 IP 白名单。

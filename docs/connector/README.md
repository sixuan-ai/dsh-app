# xHarness 电脑连接器

安装一次电脑端组件，之后用手机 App 的「连接我的电脑」导入二维码即可。现阶段支持 Linux + systemd 用户会话；不包含 Windows/macOS 安装器。

## 安装与配对

先安装 DeepSeek Harness，并使用它自己的正常启动方式运行 Web 服务。连接器默认寻找 `127.0.0.1:18395` 或 `127.0.0.1:3080`，并读取 `~/.dsh/dsh-desktop.log` 中的启动授权信息。不会重启已有 DSH，也不会复制或删除工作区。

在仓库根目录运行：

```bash
bash server/connector/install.sh --name '我的电脑'
```

依赖：Python 3.10+ 及 venv、Node.js 20+、OpenSSL、systemd 用户会话。安装脚本在独立 venv 安装固定版本 qrcode；发布压缩包附带该 wheel，可离线安装二维码依赖。DSH 需预先安装。本机已有服务使用其他端口或日志路径时：

```bash
bash server/connector/install.sh --dsh-url http://127.0.0.1:18395 --token-file /绝对路径/dsh.log
```

已有 DSH 由 systemd 用户服务启动且授权信息只写入 journal 时，可直接读取该服务日志，无需重启或修改原服务：

```bash
bash server/connector/install.sh --name x-26 \
  --dsh-url http://127.0.0.1:3080 --token-unit dsh-web.service
```

认证桥仅在启动、授权刷新或上游拒绝旧 Cookie 时读取指定用户服务最近日志；不会把启动授权码返回给手机。服务名使用独立参数传递，不调用 shell 执行日志内容。

没有运行中的 DSH 但已安装 `dsh` 时，会创建独立的 `xharness-dsh.service`。首次安装失败会保留诊断配置，修复依赖后再次运行同一安装脚本即可恢复，不会轮换已有密钥。

完成后在电脑应用菜单打开 **xHarness 电脑连接器**。也可执行：

```bash
~/.local/share/xharness-connector/venv/bin/python \
  ~/.local/share/xharness-connector/runtime/connector.py open
```

电脑生成二维码，手机与电脑连接同一网络，在 App 中点 **连接我的电脑 → 拍摄二维码 / 从相册导入**。也可以粘贴配对链接或配对文件内容；确认电脑名称、入口和证书指纹后连接。这里是拍照识别二维码，不是持续相机扫码。二维码 2 分钟有效、一次领取；过期或已用请重新生成。二维码不能作为永久邀请链接分享。

默认选择电脑默认路由对应的局域网地址，多网卡电脑可从列表切换。访客 Wi-Fi、AP 隔离或系统防火墙可能阻止连接；需要允许可信局域网访问电脑 TCP 3082。请勿为了连手机而开放原始 DSH 端口。证书由配对二维码固定，不需要在手机系统中安装根证书。

支持保存多台配对电脑，并保留原账号的电脑列表。可在连接中心选择电脑，各电脑使用独立密钥与缓存；忘记一台电脑不会移除其他电脑。电脑 IP 改变后可重新配对，已有公网入口仍可用于回退。手机丢失时在电脑撤销对应设备；手机「忘记」只删除本地保存信息，不能代替电脑撤销。

## 可选公网连接

普通用户不需要开放路由器端口，也不需要在手机安装 Tailscale。电脑和公网网关需要先加入管理员授权的同一 Tailscale 网络。**目前仍有这一步管理员接入，不宣称面向任意用户的全自动公网穿透。**

网关管理员一次性部署（已有 HTTPS nginx 与 DSH 账号目录）：

```bash
sudo python3 server/connector/deploy_hub.py \
  --origin https://你的网关域名 \
  --nginx-site /etc/nginx/sites-available/对应站点 \
  --accounts /etc/dsh-directory/users.json
```

先审核该站点配置并确认没有占用 `/connector/` 路由。安装器保留 vhost 备份，测试 nginx 配置后才 reload；新 relay 仅监听回环 3087，原站点 `/` 入口保持不变。

给网关节点授予访问获准电脑 Tailscale IPv4 地址 TCP **3082** 的 ACL/防火墙规则。不要把授权扩展至整个局域网。注册服务只接受 Tailscale `100.64.0.0/10` 中的 IPv4 及 3082 端口，并验证桌面证书及注册密钥 HMAC 证明；测试模式的回环放行仅供隔离测试，不得设置到生产服务。

网关新增：

| 组件 | 用途 |
| --- | --- |
| `xharness-hub.service` | 账号校验、电脑登记、HTTPS 固定证书转发、设备请求路由 |
| `xharness-accounts.service/.path/.timer` | 把现有账号目录导出成加盐密码校验散列，监视变更并每 60 秒核对 |
| `/var/lib/xharness-hub/registry.json` | 电脑归属、Tailscale 地址与指纹，无用户密码或桌面注册密钥 |
| `/var/lib/xharness-accounts/accounts.json` | 只读密码校验散列；hub 无权读取原账号明文目录 |
| `/etc/nginx/snippets/xharness-connector.conf` | `/connector/` 的 HTTP 与 WebSocket 转发 |

现有目录账号是首次登记公网入口的身份凭据。账号删除后，新的公网请求会在散列同步后失效；这是最终一致的，不是瞬时注销，已打开的连接不会因账号目录修改立即关闭。需要立即撤销某台手机时，在电脑撤销设备，现有 WS 也会关闭。

用户在桌面管理页填写自选网关的 HTTPS 地址、账号与密码，点「注册我的电脑」。密码只发送到所选网关，不保存在桌面；之后重新生成二维码并重新配对手机，将该电脑的公网入口同步到手机。注册成功不会给其他账号转移电脑归属。

手机启动或连接恢复时先探测已配对局域网入口（2 秒预算），不可达则使用该电脑登记的公网入口；支持在连接中心手动切换。同电脑切路由沿用任务与缓存范围，不会改连作者服务器。公网网关可见转发流量内容，本方案不是手机到电脑的端到端加密隧道；请使用自己信任的网关。

## 运维命令

下文的 `connector.py` 使用安装目录下 venv 的 Python 执行，可加 `--state /专用数据目录`（选项放在子命令前）。安装目录默认 `~/.local/share/xharness-connector`，权限 0700；密钥与设备数据 0600，不应提交或上传。

| 命令 | 作用 |
| --- | --- |
| `doctor` | 服务、DSH、认证桥、TLS 身份、公网可达性诊断；不输出凭据 |
| `pair --host 192.168.1.10` | 指定本机地址生成配对 JSON / SVG |
| `devices` | 列出设备名称、标识、时间和撤销状态 |
| `revoke device-…` | 撤销设备并关闭它已有的 WebSocket |
| `remote --gateway https://网关 --username 账号` | 交互输入密码登记公网入口 |
| `update` | 从当前安装包更新连接器代码；保留电脑身份、证书和配对 |
| `repair` | 恢复自己的 systemd 单元，保留电脑身份和配对 |
| `uninstall` | 停止并移除自己的服务及桌面快捷方式；保留配置和密钥，不删除工作区 |

重复运行 `install.sh` 会 update + repair。不要移动已安装的 venv；程序运行文件已经复制到持久安装目录，可以移走下载的安装压缩包。

用户服务默认在登录后启动；如需无人登录时启动，由管理员配置相应账号的 systemd linger，并确认原 DSH 同样支持此运行方式。

本机组件：

| 入口 | 服务 | 作用 |
| --- | --- | --- |
| `0.0.0.0:3082` HTTPS | `xharness-connector.service` | 手机设备认证、配对、撤销、HTTP / WS 转发 |
| `127.0.0.1:3083` HTTP | `xharness-auth-bridge.service` | 独立内部认证与 DSH 启动令牌 Cookie 兑换 |
| 保留原 DSH 地址 | 既有服务；或新装 `xharness-dsh.service` | 工作区、任务与模型会话 |
| 随机回环端口 | 打开管理器时启动的 Python 进程 | 一次性启动凭据换 HttpOnly/SameSite 会话，30 分钟过期 |

旧 3081 入口保持兼容，旧账号/配置不会被静默迁移到新配对。新 App 在主动配对后保存旧路由备份，忘记配对时恢复；新设备密钥放在系统安全存储，不放 SharedPreferences，也不发往官网社交、更新或管理 API。

网关回退：去掉 vhost 中 `/etc/nginx/snippets/xharness-connector.conf` 的 include（或恢复安装时备份），先 `nginx -t` 再 reload，停止 `xharness-hub`、`xharness-accounts.path`、`xharness-accounts.timer`；保留 registry 便于恢复。该操作只停新连接器公网路由，原有 DSH 入口不变。

## 验证

```bash
~/.local/share/xharness-connector/venv/bin/python -m unittest discover \
  -s server/connector -p 'test_*.py'
node server/tests/dsh-auth-proxy-auth.cjs
flutter analyze
flutter test
flutter build apk --release
```

测试使用临时证书、合成账号与假上游，不读取生产密钥；桌面二维码测试需要 venv 中的 qrcode。实际部署协议检查可使用 `tool/connector_smoke.dart`，从 stdin 输入临时设备凭据，结束后在电脑撤销测试设备；不要把密码放命令行或提交为测试固定值。该检查只读取主机信息和会话列表，不发起任务。

### 手机/云端无法浏览文件夹

若提示 DSH 使用桌面原生文件夹选择器，升级连接器；新建的托管 DSH 服务会清空显示环境变量，让 DSH 使用远程浏览模式。连接器不会修改用户已有的 DSH 服务。已有服务可自行添加 systemd drop-in（将 `<unit>` 替换为实际 DSH 单元名）：

```sh
systemctl --user edit <unit>
```

写入：

```ini
[Service]
Environment=DISPLAY=
Environment=WAYLAND_DISPLAY=
```

然后运行：

```sh
systemctl --user daemon-reload && systemctl --user restart <unit>
```

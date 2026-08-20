# DSH App

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)(DSH)的 Flutter 手机客户端,通过 DSH Web 服务器的 HTTP + WebSocket API 连接,复刻网页版核心功能:在手机上发起会话、看流式输出、处理审批与提问、切换模型与推理强度。

## Hermes Agent 品牌视觉

<p align="center">
  <img src="assets/branding/hermes-agent-icon-512.png" width="128" alt="Hermes Agent 应用图标">
</p>

### 应用市场封面

![Hermes Agent 应用市场封面：把智能体装进口袋](assets/store/hermes-agent-cover-01.png)

![Hermes Agent 应用市场封面：从指令到完成](assets/store/hermes-agent-cover-02.png)

![Hermes Agent 应用市场封面：关键步骤由你掌控](assets/store/hermes-agent-cover-03.png)

> 同目录另提供 Google Play `1024 × 500` 特性图：`assets/store/hermes-agent-google-play-feature.png`。

## 功能

- 内置默认服务器地址,启动自动连接,只需输入用户名/密码(凭据本机保存)
- 会话列表按**工作区(目录)分组**,支持折叠(状态跨启动保留);新建 / 重命名会话
- 新建会话可**选择工作区目录**:默认工作区一键创建,或从已注册工作区 / 自定义路径选择;对话中新建自动继承当前工作区
- 对话视图:历史分页加载、用户渐变气泡、助手 Markdown 渲染(代码块 / 引用 / 表格)、思考过程折叠卡、流式打字指示器
- 工具调用卡片(参数 / 结果,可折叠,状态色条 + 错误高亮)
- 审批请求(允许一次 / 拒绝)与 ask-user 提问(单选 / 多选 + 自定义文本)对话框
- 运行统计条:轮次 / 耗时 / 首 token / tok/s / 缓存命中 / 输入输出 token / 上下文占用进度条
- 模型选择:模型目录 + **推理强度**选择,切换有明确反馈
- 本地 SQLite 缓存:聊天记录与会话列表冷启动秒开,弱网先显后刷新
- 等级系统:按对话次数升级,抽屉显示等级徽章与进度,升级有庆祝提示
- 内置更新日志:抽屉入口 + 版本更新后自动弹"新功能"提示
- **社区**:发布动态、点赞、一键分享等级卡片;**好友**:8 位好友码互加、等级排行榜、私聊(未读角标)
- **应用内更新(OTA)**:启动自动检查 + 抽屉手动检查,发现新版本后带进度下载并调起系统安装器覆盖安装
- 断线自动重连(3 秒退避,重连后刷新会话与历史)

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

## 社交服务(好友 / 社区 / 私聊)

社区功能由 `server/social-server.py` 提供 —— 零依赖 Python 脚本(标准库 + sqlite3),部署在公网服务器上,由 nginx 在 `/social/` 下反代并复用同一份 Basic 认证:

```sh
# 公网服务器上:
mkdir -p /opt/dsh-social && cp server/social-server.py /opt/dsh-social/
# systemd 常驻:
#   ExecStart=/usr/bin/python3 /opt/dsh-social/social-server.py(监听 127.0.0.1:9981)
# nginx 443 server 块加(server/nginx-dsh.conf.sample 已含):
#   location /social/ { proxy_pass http://127.0.0.1:9981; auth_basic ...; }
```

设计要点:

- 外层 Basic 认证(nginx)挡陌生人;应用内身份是注册时签发的 `x-social-token`,手机本机保存
- 好友码是注册时分配的 8 位数字,互加即成为好友(无需确认流程,小圈子够用)
- 等级以客户端上报的 promptCount 为准,服务端用与 App 相同的阈值表折算称号;排名只认服务端最后上报值
- 私聊是轮询模式(聊天页 4 秒、会话列表 10 秒),未读数由服务端按"已读水位"计算
- 数据在 `/opt/dsh-social/social.db`,备份这一一个文件即可

## 应用内更新(OTA)

App 启动后自动拉取更新清单,发现新版本就弹窗,确认后带进度下载 APK、校验 sha256、调起系统安装器覆盖安装 —— 日常更新不再需要数据线。抽屉里也有"检查更新"手动入口。

**更新源结构(公网服务器上):**

```
/var/www/dsh-releases/
  latest.json            # {"version","versionCode","url","notes","size","sha256"}
  dsh-app-1.3.0.apk      # 各版本 APK
```

**公网服务器一次性配置:**

1. nginx 443 server 块内加(`server/nginx-dsh.conf.sample` 已含):

   ```nginx
   location /releases/ {
       alias /var/www/dsh-releases/;
       auth_basic "dsh releases";
       auth_basic_user_file /etc/nginx/.htpasswd-dsh;
       autoindex off;
       add_header Cache-Control "no-store";
   }
   ```

2. 建密码文件(App 会复用登录凭据下载,建议和认证代理同一组):

   ```sh
   htpasswd -bc /etc/nginx/.htpasswd-dsh 用户名 密码
   mkdir -p /var/www/dsh-releases
   nginx -t && systemctl reload nginx
   ```

**发布新版本(开发机上):**

```sh
# 1. bump pubspec.yaml 的 version: x.y.z+N
# 2. 在 lib/src/changelog.dart 顶部加一条记录并同步 kAppVersion
SERVER_PASSWORD=服务器密码 tool/publish.sh
```

脚本自动构建 release APK(arm64 单架构,debug 密钥签名可直接覆盖)、计算 size/sha256、生成 latest.json 并 scp 上传。**注意**:`--split-per-abi` 会给 versionCode 加架构偏移(arm64 为 +2000),脚本用 aapt 从 APK 里读真实 versionCode 写进清单,手机端比较才不失真 —— 不要手写清单里的 versionCode。

**开发期用局域网加速测试:** 在开发机上 `mkdir /tmp/releases && cp app-release.apk latest.json /tmp/releases/ && (cd /tmp/releases && python3 -m http.server 8000)`,把 `lib/main.dart` 的 `kUpdateManifestUrl` 临时改为 `http://电脑IP:8000/latest.json`(无认证,凭据不校验),手机同一 Wi-Fi 即可秒下。测完改回公网地址。

## iOS / App Store 准备

iOS 工程已生成并预配好(Mac 上无需再 `flutter create`):

- `ios/Runner/Info.plist` 已含:`NSAllowsLocalNetworking`(局域网 HTTP 直连自建服务器)、`ITSAppUsesNonExemptEncryption = false`(免加密出口申报问答)
- OTA 自更新仅 Android 编译(Apple 条例 2.5.2 禁止绕过商店安装代码);iOS 的测试分发走 **TestFlight**

Mac 上的步骤:

1. 装 Xcode(App Store)→ `sudo xcodebuild -license accept`;装 CocoaPods(`brew install cocoapods`)
2. 装 Flutter SDK,`flutter doctor` 全绿
3. clone 本仓库,`flutter pub get`
4. 注册 Apple Developer 账号($99/年,需实名),Xcode → Settings → Accounts 登录
5. `open ios/Runner.xcworkspace` → Signing & Capabilities 选你的 Team;Bundle ID 按需从 `dev.dsh.dsh_mobile` 改成自己的
6. 真机调试 `flutter run`;出包 `flutter build ipa`,用 Xcode Organizer / Transporter 上传
7. App Store Connect 建 App:6.9"/6.5" 截图、隐私政策 URL、年龄分级;**审核信息里填演示账号密码**,并保证审核期间你的 dsh 服务器在线

## 构建与安装

```sh
flutter pub get
flutter analyze && flutter test
flutter build apk --debug          # 输出 build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## 目录结构

```
lib/
  main.dart            UI:登录页、主页、抽屉(工作区分组+等级)、聊天气泡、模型选择、更新日志页
  state.dart           AppState:连接生命周期、事件折叠、投影、模型、等级计数
  src/protocol.dart    DSH Web 线协议:一元 RPC、WS 下行流、审批/提问应答(纯 Dart,无 Flutter 依赖)
  src/localstore.dart  SQLite 本地缓存:聊天记录、会话列表、对话计数
  src/changelog.dart   内置更新日志数据(发版时在顶部加一条并同步 kAppVersion 与 pubspec 版本号)
  src/updater.dart     应用内更新:清单拉取、版本比较、带进度的 APK 下载、sha256 校验、安装通道
server/
  dsh-auth-proxy.js    认证代理:Basic 认证 + 登录页 + Host 改写 + 防爆破(零依赖 Node 脚本)
  frpc-dsh.toml.sample dsh 电脑上的 frpc 配置样例
  nginx-dsh.conf.sample 公网服务器 nginx 配置样例
tool/smoke.dart        协议冒烟测试
tool/publish.sh        一键构建 + 发布 OTA 更新到公网服务器
test/state_test.dart   事件折叠 / 序列化 / 等级计算单测
```

## 安全注意

- Basic 认证是公网部署**唯一**的访问控制:密码要够长,泄露后立即更换(AUTH_PASSWORD + 手机登录页)。
- 凭据明文保存在手机 SharedPreferences 中;不要共享安装包给不信任的人。
- dsh web 本身等价于远程代码执行,**永远**不要绕过代理直接把它暴露到任何网络。

# xHarness

DeepSeek Harness(DSH)的 Flutter 手机客户端,通过 DSH Web 服务器的 HTTP + WebSocket API 连接,复刻网页版核心功能:在手机上发起会话、看流式输出、处理审批与提问、切换模型与推理强度。

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

- **可选登录**：无需登录即可使用局域网、已配对电脑的公网入口与默认公网服务、多电脑切换、工作区、任务与模型选择；App 不按登录状态限制电脑数量或任务次数。登录为账号同步/注册的可选入口，操作权限始终遵循电脑端授权。
- **思玄邮箱账号**：App 内注册、邮箱和密码直接登录、邮箱验证码找回密码；退出账号保留电脑入口、配对与当前连接。兼容旧 DSH 账号电脑入口。
- **大肥鱼互动**：使用默认鲸尾女仆形象与动画，上下文累计 1M 对应一碗白米饭，支持自动吃饭成长与手动互动；来源、许可和压缩记录见 [资源说明](docs/pet/DAFEIYU.md)。
- 可配对自己的 DSH 电脑：一次性二维码、独立设备密钥、HTTPS 证书校验、局域网优先与已配置公网回退；兼容旧账号登录
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

## 连接自己的电脑

从 2.2.0 起无需修改 App 常量或重新打包。推荐使用本仓库的 Linux 电脑连接器：

1. 在电脑安装并启动 DeepSeek Harness（DSH），保持其原生服务只监听回环地址。
2. 在仓库根目录运行 `bash server/connector/install.sh`，然后在电脑应用菜单打开 **xHarness 电脑连接器**。
3. 手机和电脑连接同一网络，在电脑生成一次性二维码；App 点 **连接我的电脑**，拍摄或导入二维码，核对电脑名称后确认连接。
4. 需要公网时，App 无需登录；电脑完成 Tailscale 登录并由网关管理员授权，然后在连接器填写网关 HTTPS 地址及账号，注册电脑后重新配对手机。

局域网使用固定证书的 HTTPS；配对码 2 分钟有效且只能使用一次，手机获得独立设备凭据，电脑可逐台撤销。已注册公网的电脑在启动或断线恢复时优先尝试局域网，再尝试该电脑的公网入口。工作区、项目进度与任务对话来自同一台 DSH。

**当前范围：**电脑安装器支持 Linux + systemd 用户会话，需要 Python 3.10+（含 venv）、Node.js 20+、OpenSSL，以及已安装的 DSH。Android 已构建并进行协议验证；Windows/macOS 安装器和 iOS 实机配对尚未验收。支持保存多台配对电脑，并保留原账号的电脑列表。公网网关首次部署和 Tailscale 授权仍由管理员完成，手机无需安装 Tailscale。

- [安装、使用、维护与卸载](docs/connector/README.md)
- [实现与验收结果](docs/connector/IMPLEMENTATION.md)
- [历史手工部署记录](docs/connector/LEGACY-CONNECTIONS.md)

作者现有账号登录入口 `https://dsh.sixuanai.com` 保留兼容；它不会自动绑定到每位使用者的个人电脑。

### 2.7.0 账号与权限规则

欢迎页、连接中心和连接教程均提供「功能与权限」说明。未登录时可使用局域网与公网中的已授权电脑，模型与工具由电脑提供；命令执行、文件修改和完全权限不会因登录而自动开放。公网入口不要求 App 账号登录，电脑端配对、Basic 认证和授权规则保持不变；局域网切换不依赖公网目录服务。账号同步和云端设备备份尚未提供。

App 当前复用 `https://accounts.sixuanai.com` 的独立邮箱账号服务：注册和找回密码验证邮箱，`POST /api/app/login` 使用邮箱与密码签发会话；账号会话保存在系统安全存储，与电脑的配对密钥分开。此仓库包含 Flutter 客户端和 DSH 电脑连接器，邮箱账号服务独立部署；自建账号服务时需提供对应接口并调整 `lib/src/sixuan_account.dart` 中的服务地址。

Android 2.6.2 发布包的 arm64 版本号为 **2148**。当前下载：[Android APK](https://downloads.ainotex.com/xharness/dsh-app-2.6.2.apk)，亦可使用 App 内检查更新。下载发布流程见 [Cloudflare 下载与维护](docs/releases/CLOUDFLARE_DOWNLOADS.md)。

## 产品官网

产品官网为 [sixuanai.com](https://sixuanai.com)，源码在独立的网站工程维护，不包含在此仓库。原 `server/site` 已移除；本仓库的连接器和下载服务运维见 [运维说明](server/OPERATIONS.md)。

APK 发布与 App 内容渠道仍按原项目流程维护；目录整理不代表迁移下载服务。

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
  social-server.py     社交后端:好友/动态/私聊/头像(零依赖 Python + sqlite3)
  connector/           Linux 电脑连接器、HTTPS 配对、桌面管理页及公网网关
  release-cdn.example.json Cloudflare 下载发布配置示例（实际配置不提交）
  frpc-dsh.toml.sample dsh 电脑上的 frpc 配置样例
  nginx-dsh.conf.sample 公网服务器 nginx 配置样例
tool/smoke.dart        协议冒烟测试
tool/publish.sh        一键构建 + 发布 OTA 更新到公网服务器
test/state_test.dart   事件折叠 / 序列化 / 等级计算单测
```

## 访问权限

- 配对手机可以操作本机 DSH 的工作区和任务。请核对电脑身份，只向自己的手机展示配对码；在电脑管理页撤销不再使用的设备。
- 新配对的设备密钥存入系统安全存储，电脑保存加盐散列；Android 禁止应用数据备份，避免密钥与其他设备混用。
- 旧账号登录仍使用原有凭据保存方式；新配对模式的设备凭据不用于官网账号、社交或管理服务。配对不改变 DSH 自身的工具执行和审批设置。
- 新连接器复用 DSH 回环服务，通过独立认证桥转发。公网网关仅允许注册的 Tailscale 地址和指定连接器端口，并校验证书与注册密钥持有证明。

## 鸿蒙版本

鸿蒙适配副本位于本地 `harmonyos/` 子目录，构建说明见 [harmonyos/HARMONYOS.md](harmonyos/HARMONYOS.md)。该目录是独立代码快照，与主项目不会自动同步；源码随本仓库维护，签名材料、本地配置和构建缓存已排除提交。

## 开源许可

本项目以 [MIT License](LICENSE) 开源。你可以自由使用、修改、商用和再分发，只需保留版权声明。

第三方动画资源另附 [资源许可](assets/pet/dafeiyu/LICENSE.txt) 与 [来源记录](assets/pet/dafeiyu/provenance.json)，使用时请一并保留相应版权与许可声明。

需要说明的边界：许可证只覆盖**代码**，不包含作者自用的托管实例、域名和部署环境——
README 与代码里出现的 `dsh.ainotex.com`、`dsh.sixuanai.com` 等地址只是作者自己的部署，
随时可能变化或下线；自建请参考 `server/` 下的样例（`dsh-auth-proxy.js`、`frpc-dsh.toml.sample`、
`nginx-dsh.conf.sample`、`server/registration/`）自己搭一套。

欢迎提 issue / PR。改动协议层时请先跑 `tool/smoke.dart` 和 `flutter test`。


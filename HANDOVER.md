# xHarness 项目交接文档

> 写给下一段对话的 agent：读这份文档 + `server/OPERATIONS.md` 即可无缝接手。
> 最后更新：2026-08-21（v1.9.2+28，main `42e5fc3`）

## 0. 三十秒速览

**xHarness** 是一个 Flutter Android App，通过公网链路连接用户的 DeepSeek Harness(dsh)
实例，替代/增强 dsh 网页 GUI(http://127.0.0.1:3080)。已有：完整对话体验、四套主题、
社区社交、OTA 自更新、多实例登录。基础设施（Cloudflare + HK nginx + frp + systemd)
已完成速度/稳定性/安全性加固。

**下一步大方向（用户尚未拍板，开工前先问）**:Phase 1 核心体验补全 ——
图片消息(1.1)→ 会话管理(1.2)→ 消息搜索(1.3)→ 子代理可视化(1.4)→ 会话导出(1.5)。
详见 §6。

## 1. 代码与路径

| 内容 | 路径 |
|---|---|
| Flutter App 仓库(主战场) | `~/code/pd02/dsh_mobile`(git: `git@github.com:zhaojiaxiang370711/dsh-app.git`) |
| dsh 实现源码(查协议/行为用) | `~/code/pd02/deepseek-harness`(master ≈ 线上 rc.8) |
| 线上实际运行的 dsh 包 | `/home/x/.npm/_npx/73d55d6bf82710ec/`(`dsh web` 进程,**绝不重启**) |
| 运维手册(链路/操作/排障) | `server/OPERATIONS.md`(仓库内,先读) |
| 发布脚本 | `tool/publish.sh`(SSH 密钥认证,用法见 §4) |
| 社交后端(部署在 HK) | `server/social-server.py` → HK `/opt/dsh-social/` |

Flutter SDK:`/home/x/flutter/bin`(每次 `export PATH`);Android build-tools 37(aapt 在
`$ANDROID_HOME/build-tools/`);测试手机 Xiaomi/HyperOS adb id `e516d50e`(时连时断)。

## 2. 访问与凭证(只记位置)

| 凭证 | 位置 |
|---|---|
| HK SSH(47.239.235.154) | **仅密钥**,本机 `~/.ssh/id_ed25519` 已在 authorized_keys,直接 `ssh root@...` |
| Cloudflare API 令牌 + zone id | `~/.bashrc` 的 `CF_API_TOKEN` / `CF_ZONE_AINOTEX`(权限 600) |
| Basic 认证(x 用户,网页/App/OTA/社交共用) | 明文存于 HK `/etc/dsh-directory/users.json`;htpasswd 在 `/etc/nginx/.htpasswd-dsh` |
| directory 用户表(x/mac → 各自实例子域) | 同上 users.json |
| auth-proxy 的 AUTH_* env | 本机 `systemctl cat dsh-web-auth.service` |
| frp token | 本机 `/etc/frp/frpc-*.toml` 与 HK `/root/app/frpc/frps.toml` |
| App 正式签名(v1.10.4 起) | keystore `android/app/dsh-release.jks` + 密码 `android/key.properties`(均 gitignore 不入库,**务必离线备份**;丢了永远无法同签名更新)。证书 SHA-256 `b7fa2a09…22d06d1`,MD5 `8a8a64f89ab9311f607a2b80c41fc222`(备案用) |

**注意**:多份凭证曾出现在旧聊天记录,轮换清单见 OPERATIONS.md §6。

## 3. 链路拓扑(详图见 OPERATIONS.md §1)

```
手机 → Cloudflare 边缘(APK 缓存,SSL Full strict)
     → HK nginx :443(强制 HTTPS/HSTS/gzip/限流)
     → frp QUIC 隧道(TLS+压缩+心跳)
     → 本机 auth-proxy :3081 → dsh web :3080
双实例:directory 服务(HK:3085)按用户名路由 x→主域 / mac→mac.dsh.ainotex.com
集中后端(只在主域):/releases/(OTA)、/app/(官网)、/social/(社交)、/directory/
```

## 4. 开发工作流(每个版本都走这套)

```bash
export PATH="/home/x/flutter/bin:$PATH"; cd ~/code/pd02/dsh_mobile
# 1. 改代码 → flutter analyze(必须零问题) → flutter test(当前 19 个)
# 2. pubspec.yaml version 加一 + lib/src/changelog.dart 加条目(kAppVersion 同步)
# 3. NOTES='更新摘要' tool/publish.sh   # 构建+上传 OTA,密钥认证免密
# 4. git add -A && git commit && git push
```

关键坑(都踩过,别再踩):

- **split-per-abi versionCode 偏移**:arm64 +2000。publish.sh 已用 aapt 读真实值,勿改回读 pubspec
- `bool.fromEnvironment('X')` 只认值 `true`(不是 `1`)
- **Xiaomi HyperOS/Impeller**:Transform 包裹的 Image 渲染全黑 —— 用 CustomPaint+drawImageRect(见头像裁剪页)
- **Xiaomi HyperOS/Impeller 其二**:Ink+BoxDecoration 渐变不绘制(无异常,静默跳过)——浅色主题下白箭头落在白卡片上=按钮隐形但可点(v1.10.0 发送按钮悬案)。圆形按钮一律用 Container+IconButton,别用 Ink
- MIUI 禁止 `adb shell input` 注入;真机验证用 logcat print + screencap 像素分析
- 修改 main.dart 字符串补丁要用 edit 工具,python/sed 曾两次毁文件(可用 `git checkout` 恢复)
- analyzer 约定:null-aware 元素 `'k': ?v`、无 `Colors.white45`、CardThemeData/DialogThemeData

## 5. dsh 协议要点(已实测验证)

- 一元 RPC:`POST /api/<method>`,信封 `{type:'client-request',rpcId,method,payload}`
  → `{type:'server-response',rpcId,result:{ok,value}|{ok:false,error}}`
- WS 下行:`/api/events.mux`(会话事件)+ `/api/events.host`(会话生命周期);应答 `/api/respond`
- **斜杠命令**:`session.prompt` 不解析 `/`;走 `commands/execute`,
  payload `{args:{agentId:<sessionId>, line:'/compact', images:[]}}`;
  目录 `commands/list` 同参;生命周期事件 `command/run`+`command/done`(按 commandId 配对,
  App 已折叠为"回声气泡+进行中→结果")
- 提问/审批:server-request 经 mux 推送,`/api/respond` 应答;
  **respond 返回 accepted=false 表示已失效**(v1.9.2 起 App 有提示)
- session.history 分页:10 条首批/15 条翻页,beforeSeq 对齐
- 未用但存在的 RPC(Phase 1 素材):`session.attachment`(图片)、`session.search`、
  `workspace.archiveSession/delete`、`subagent.list/history`

## 6. 路线图(用户已认可框架,优先级未定)

- **Phase 1 核心体验补全**(App 完全替代网页版):1.1 图片消息(服务器 session.attachment
  已支持)→ 1.2 会话删除/归档/置顶 → 1.3 消息搜索 → 1.4 子代理可视化 → 1.5 会话导出
- **Phase 2 社区深化**:帖子图片/评论、私聊图片、社交多用户化(mac 用户当前 /social/ 401)
- **Phase 3 平台扩展**:iOS(MacBook Air + TestFlight;ios/ 已生成,OTA 已按平台门控)、平板适配
- **Phase 4 账号与产品化**:directory+Basic+社交账号三合一、官网内容完善、多用户开放

## 7. 当前状态快照(v1.18.1)

App 功能:登录(远程/本地连接选择、无需退出的一键切换、本地 DSH 健康检测、directory 路由/实例记忆、电脑端配置教程、安全提醒、友好错误提示、首次快速上手)、会话(含 assistant 生成图片回显、持久附件加载和全屏预览)(分组/折叠/重命名/新建继承 cwd/运行中与归档筛选/本地置顶/服务端归档)、图片消息(相册/拍照/压缩/图文发送/历史附件读取/预览)、
对话(markdown/流式/工具卡/时间分隔/回到底部按钮/长按复制/入场动画)、斜杠命令
(⊕ 面板+实时目录+进度反馈,面板已修:命令多时可滚动)、模型切换(含推理强度)、
统计栏、四套主题(暗夜蓝/纯净白/护眼绿/樱花粉)、社区(动态/好友码/私聊/等级/
头像裁剪)、**宠物(领养/喂食/玩耍/洗澡,状态随时间衰减;成长按累计缓存命中 tokens 计,1M/级,五物种神秘蛋进化(哈灵/雷光猫/苍月狼/焚天炎龙/九天凤凰,宝可梦风命名)+庆祝弹窗+破壳彩蛋,宠物对战赢取代币,人机匹配+段位系统,原创Q版矢量精灵立绘)**、
抽屉权限模式入口(工作区写入/完全访问+风险确认)、抽屉底部仅社区+「更多功能」九宫格
(主题/宠物/权限/更新/日志/退出,红点透传)、
系统通知、OTA 自更新(美化弹窗+圆环进度+网速+重试)、更新日志、断线指数退避重连。
审批/提问弹窗:PopScope 防返回键误关+未回答自动重弹+他端回答后联动关闭(双端同步);
发送/私聊圆形按钮 Ink→Container(HyperOS 渐变不绘制导致隐形,见 §4 坑)。

基础设施:全部 systemd 化(HK frps/dsh-social/dsh-directory,本机 frpc×2/dsh-web-auth);
nginx 双 vhost 加固;CF 边缘缓存(APK HIT ~6MB/s);SSH 密钥-only;OPERATIONS.md 运维手册。

## 8. 未决事项 / 风险

1. 会话管理已支持筛选/置顶/归档;当前 host 仅暴露 `workspace.archiveSession`,没有删除或取消归档 RPC,因此这两项必须等协议补齐,不能只删手机缓存伪装成功
2. Mac 实例的 dsh web 平时不在跑(唤醒即用);mac 用户社交 401(待社交多用户化)
3. 本机两个隧道 sshd(22022/22023)仍是裸进程,可 systemd 化
4. 凭证轮换清单未执行(OPERATIONS.md §6)
5. dsh web(3080)是某段对话的 GUI,**任何时候都不要重启它**
6. 用户手机需要退出重登一次才会走 directory 路由(v1.9.0+)

## 9. 给新对话的开场白(用户可直接粘贴)

> 读 `~/code/pd02/dsh_mobile/HANDOVER.md` 和 `server/OPERATIONS.md`,接手 xHarness 项目。
> 当前版本 v1.18.1,我想从 Phase 1 的 ___ 开始(或:先聊聊优先级)。

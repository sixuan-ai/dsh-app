# xHarness 项目交接文档

> 写给下一段对话的 agent：先读本文件，再按任务需要读 `server/OPERATIONS.md`。
> 最后更新：2026-08-23（v1.22.2+63；App 发布提交以 main 最新为准）

## 0. 三十秒速览

**xHarness** 是 DeepSeek Harness 的 Flutter 手机客户端，通过公网链路连接用户的 DSH 实例。当前已经不是原型：对话、图片、权限、子代理、宠物、社区、AI 日报、OTA、本地缓存、断线恢复和多实例登录都已可用。

当前最新正式版：

```text
版本: v1.22.2
versionCode: 2063
APK: https://dsh.ainotex.com/releases/dsh-app-1.22.2.apk
SHA-256: 1bb23c4de0662cb6b0b2a9c9d6617506ed86373ca2a471fb9bcb212da4b7db31
Git: 以 main 最新发布提交为准
```

当前最重要的下一件事：**如果长对话恢复仍然慢，需要给 DSH 服务端 `session.history` 增加 `afterSeq` 增量接口**。App 侧已经改成游标判断 + 小尾部合并 + 后台补齐缺口，剩余瓶颈在服务端历史读取。

## 1. 代码与路径

| 内容 | 路径 |
|---|---|
| Flutter App 仓库 | `/home/x/code/pd02/dsh_mobile` |
| App GitHub | `git@github.com:zhaojiaxiang370711/dsh-app.git` |
| DSH 源码参考 | `/home/x/code/pd02/deepseek-harness` |
| 当前 DSH 配置 | `/home/x/.dsh/settings.yaml` |
| 运维手册 | `/home/x/code/pd02/dsh_mobile/server/OPERATIONS.md` |
| 发布脚本 | `/home/x/code/pd02/dsh_mobile/tool/publish.sh` |
| AI 日报内容 | `/home/x/code/pd02/dsh_mobile/server/site/content/ai/news.json` |
| Agent 学习内容 | `/home/x/code/pd02/dsh_mobile/server/site/content/ai/agents.json` |
| 本地图片生成工具 | `/home/x/code/pd01/tools/image-gen/gen-image` |

Flutter SDK：

```bash
export PATH="/home/x/flutter/bin:$PATH"
```

不要把 `/home/x/code/pd02/deepseek-harness` 当作 App 仓库；App 改动都在 `dsh_mobile`。

## 2. 当前功能全景

### 对话与同步

- 会话创建、选择、重命名、置顶、归档筛选、本地缓存。
- Markdown、流式回复、工具调用卡片、图片结果、长按复制、时间分隔、回到底部。
- 本地 SQLite 保存会话列表、聊天内容、历史分页位置：`oldestSeq` / `latestSeq` / `hasMore`。
- 锁屏恢复后立即重建 WebSocket，不再等超时。
- 使用 `session/subscribed.lastSeq` 判断是否需要同步。
- 有更新时只拉最新 3 条消息组并合并到本地历史，不清空聊天。
- 如果锁屏期间产生大量新消息，先显示最新进度，再后台补齐中间历史。
- 审批和提问重连重放时按 ID 去重。
- AppBar 可显示：
  - `正在同步最新进度…`
  - `正在补齐中间历史…`
  - `正在生成…`

### 权限

- 输入框旁有盾牌按钮，可在当前会话直接切换：
  - `workspace-write`
  - `danger-full-access`
- 开启完全访问前有中文风险确认。
- 与网页版一致，实际写入仍通过：
  ```text
  /permission danger-full-access
  /permission workspace-write
  ```

### 子代理

- 子代理内部会话不会出现在左侧工作区列表。
- 判断规则与 Web 一致：
  - `origin == 'subagent'`
  - 或 `projections.values.subagent != null`
- 普通 fork 不会仅因 `parentSessionId` 被隐藏。
- 当前主会话右上角有子代理状态按钮。
- 有运行中的子代理时显示绿色角标和数量。
- 点击后显示任务名称、运行中/已完成、单次/可继续、是否包含下级代理。
- 数据来自 `subagent.list`。

### 图片

- 支持相册/拍照上传图片。
- 支持用户消息、assistant 消息、工具结果中的图片。
- 图片附件按需通过 `session.attachment` 加载。
- 全屏预览支持缩放。
- 全屏预览右上角有下载按钮，保存到系统相册。
- 使用 `gal` 包保存图片；iOS `Info.plist` 已补相册写入说明。

### 模型与图片输入

- 当前模型 `kimiqx / kimi-k3` 已在 `/home/x/.dsh/settings.yaml` 声明：
  ```yaml
  input:
    - text
    - image
  ```
- 因此当前会话可以正常使用 `read_image`。
- GPT-5.6 Sol/Terra/Luna 也声明了图片输入。
- 本地 `gen-image` CLI 只支持 Gemini 图像模型：
  - `nano-banana-2`
  - `nano-banana`
  - `nano-banana-pro`
- 用户的 OpenAI 兼容中转还列出：
  - `gpt-image-1.5`
  - `gpt-image-2`
- 高质量宣传图已改为直接调用 `/v1/images/generations` 的 `gpt-image-2`，没有修改 Go 项目。

### AI 日报与 AI 知识学习

- App 不直接抓第三方 RSS，只读取本站 JSON 并缓存。
- 新闻日按北京时间 10:00 切分：
  ```text
  前一天 10:00（含）→ 当天 10:00（不含）
  ```
- 当前 AI 日报内容：
  ```text
  version: 4
  items: 19
  updatedAt: 2026-08-23T17:31:16+08:00
  ```
- 线上接口：
  ```text
  https://dsh.ainotex.com/app/content/ai/news.json
  https://dsh.ainotex.com/app/content/ai/agents.json
  ```
- 最近一次内容提交：`abb8282 扩充 AI 日报模型新闻内容`。

### 宠物与社区

- 宠物领养、喂食、玩耍、洗澡、状态衰减、token 成长、五物种进化、破壳彩蛋、对战、人机匹配、段位。
- 社区动态、好友码、私聊、头像裁剪、等级。
- 社交后端集中在主域 `/social/`。

### OTA 与更新

- App 内检查更新。
- 更新弹窗有防重复打开逻辑。
- Android 使用正式签名，签名文件只在本地，不在 Git 仓库。

## 3. 最近版本记录

### v1.22.2

- 代理错误与 turn/end 失败合并为一条卡片。
- 模型并发上限、限流、额度不足显示为可读中文提示。
- 失败后清理残留的流式占位气泡。
- 错误卡片支持一键重试最近一条纯文本用户消息。

### v1.22.1

- 长对话锁屏恢复时，最新进度优先显示。
- 中间缺失历史后台自动补齐。
- 补齐过程不覆盖本地已缓存内容。

### v1.22.0

- 锁屏恢复后立即重建实时连接。
- 使用 `session/subscribed.lastSeq` 做游标判断。
- 长对话恢复不再清空本地历史。
- 只拉取并合并最新几条消息。
- 修复重连后审批/提问重复出现。

### v1.21.0

- 已加载历史完整保存到手机本地。
- 再次打开优先本地显示。
- “加载更多”只从本地缺口继续请求。

### v1.20.1

- 图片全屏预览新增下载按钮。
- 保存到系统相册，并提供权限失败提示。

### v1.20.0

- 新增子代理运行状态入口。
- 显示运行数量、任务名称和完成状态。

### v1.19.0

- 输入框新增完全访问快捷键。
- 修复子代理内部会话混入工作区列表。

## 4. 同步与缓存设计要点

当前 App 侧恢复路径：

```text
App resumed
  → 立即替换 mux/host WebSocket
  → 接收 session/subscribed.lastSeq
  → lastSeq <= 本地 latestSeq：不请求历史
  → lastSeq > 本地 latestSeq：session.history(maxMessages: 3)
  → 按 ChatItem id 与 seq 合并最新尾部
  → 如果发现中间缺口，后台 beforeSeq 分页补齐
  → SQLite 保存 items + oldestSeq + latestSeq + hasMore
```

关键实现文件：

- `lib/state.dart`
  - `_startStreams`
  - `_replaceStreams`
  - `resyncAfterResume`
  - `syncTail`
  - `_fillHistoryGap`
  - `_mergeTailItems`
  - `_loadLocalHistory`
  - `_saveSnapshot`
- `lib/main.dart`
  - `didChangeAppLifecycleState`
  - AppBar 同步状态文案
- `test/state_test.dart`
  - seq gap 缓冲测试
  - tail merge 测试
  - 中间历史插入测试

重要限制：DSH 服务端 `session.history` 当前仍会从完整事件日志中取页。App 已减少请求次数和传输量，但如果未来仍慢，应该在 DSH 增加：

```text
session.history({ sessionId, afterSeq, maxMessages })
```

让服务器直接从本地游标之后增量返回。

## 5. 开发与发布流程

每次 App 版本：

```bash
cd /home/x/code/pd02/dsh_mobile
export PATH="/home/x/flutter/bin:$PATH"

flutter analyze
flutter test

# 修改版本
# pubspec.yaml: version: x.y.z+code
# lib/src/changelog.dart: kAppVersion + 新条目
# HANDOVER.md: 当前版本

NOTES='更新摘要' tool/publish.sh

git add -A
git commit -m "版本说明"
git push
```

发布脚本会上传 APK 和 `latest.json` 到生产站点。

## 6. AI 内容发布流程

编辑：

```bash
server/site/content/ai/news.json
server/site/content/ai/agents.json
```

要求：

- `version` 单调递增。
- `updatedAt` 更新。
- 每条新闻必须有官方来源链接。
- 优先记录“哪个公司发布了什么模型/更新”。
- 只有日期没有精确时间时，正文说明“官方页面只确认到日期”。

校验：

```bash
python3 -m json.tool server/site/content/ai/news.json >/dev/null
python3 -m json.tool server/site/content/ai/agents.json >/dev/null
flutter test test/ai_content_test.dart
```

上传：

```bash
scp -r server/site/content/ai root@47.239.235.154:/var/www/dsh-site/content/
ssh root@47.239.235.154 'chmod 644 /var/www/dsh-site/content/ai/news.json /var/www/dsh-site/content/ai/agents.json'
```

验证：

```bash
curl -fsS https://dsh.ainotex.com/app/content/ai/news.json | python3 -m json.tool
curl -fsS https://dsh.ainotex.com/app/content/ai/agents.json | python3 -m json.tool
```

注意：直接用 Python `urllib` 不带 User-Agent 访问线上内容曾返回 403；用 `curl` 或带 User-Agent 验证。

## 7. 基础设施与凭证位置

| 凭证/资源 | 位置 |
|---|---|
| HK SSH | 本机 `~/.ssh/id_ed25519`，服务器 `47.239.235.154` |
| Cloudflare API | `~/.bashrc` 的 `CF_API_TOKEN` / `CF_ZONE_AINOTEX` |
| Basic 用户 | HK `/etc/dsh-directory/users.json` |
| nginx htpasswd | HK `/etc/nginx/.htpasswd-dsh` |
| frp token | 本机 `/etc/frp/frpc-*.toml`，HK `/root/app/frpc/frps.toml` |
| App 签名 | `android/app/dsh-release.jks` + `android/key.properties`，均在 gitignore |

不要在文档或聊天记录里输出真实密钥。

## 8. 重要坑位

1. **不要重启当前 DSH Web 进程**：`http://127.0.0.1:3080` 是正在使用的 GUI。
2. Xiaomi/HyperOS 上不要用 `Ink + BoxDecoration` 做圆形渐变按钮，可能静默不绘制；用 `Container + IconButton`。
3. Xiaomi/HyperOS 上 `Transform` 包裹图片可能黑屏；图片裁剪页使用 `CustomPaint + drawImageRect`。
4. split-per-abi APK 的 versionCode 有偏移；`tool/publish.sh` 已用 aapt 读取真实值。
5. `bool.fromEnvironment` 只认字符串 `true`。
6. 修改 `main.dart` 大段内容优先用 `edit` 工具，避免脚本替换损坏文件。
7. App 侧图片附件不要把 base64 全部写入 SQLite；只存引用，按需通过 `session.attachment` 取。
8. 子代理会话绝不能进普通侧边栏；普通 fork 不能误隐藏。

## 9. 当前未决事项

1. DSH 服务端 `session.history` 还没有 `afterSeq`，极端长对话恢复仍可能受服务端全量日志读取影响。
2. `session.list` 对长 attached session 也有全量事件遍历风险；后续可考虑把 `lastSeq` 加进 `SessionSummary`。
3. 当前后台补齐中间历史每次恢复最多补 8 页；极端长缺口可能要多轮恢复才完全补齐。
4. Mac 实例社交仍有 401，需要社交多用户化。
5. 凭证轮换清单未执行，见 `server/OPERATIONS.md`。
6. iOS 还未正式发布，只是项目结构和权限说明已逐步补齐。
7. 宣传图本地临时文件在 `/tmp/dsh-images/`，重启后可能丢失；需要长期保存时应复制到仓库或对象存储。

## 10. 给下一段对话的开场白

直接粘贴：

```text
请先阅读 /home/x/code/pd02/dsh_mobile/HANDOVER.md，接手 xHarness。
当前最新版本是 v1.22.2+63；交接文档以仓库 main 分支最新内容为准。
先不要改 DSH Web 进程，也不要重启 127.0.0.1:3080。
我希望继续处理：____。
```

如果继续优化长对话同步，补上：

```text
重点看 HANDOVER.md 第 4 节。App 侧已经做了 lastSeq、tail merge 和后台补齐；下一步考虑给 DSH session.history 增加 afterSeq。
```

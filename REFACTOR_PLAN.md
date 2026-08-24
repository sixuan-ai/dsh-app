# xHarness 核心代码解耦计划

## 目标

在不改变用户界面、DSH 协议和运行行为的前提下，逐步降低 `lib/state.dart` 与 `lib/main.dart` 的职责密度，使会话事件解析、聊天折叠、连接生命周期和界面组件能够独立测试与维护。

本计划只修改 xHarness App，不修改上游 DeepSeek Harness，不修改或重启 `127.0.0.1:3080`。

## 当前基线

- `lib/main.dart`：约 6140 行，已拆出任务队列和 Composer。
- `lib/state.dart`：约 2595 行，仍集中承担连接、会话、历史、事件解析、聊天折叠、审批、模型、子代理和缓存职责。
- Flutter analyzer 无问题。
- 完整测试共 72 项，全部通过。

## 设计原则

1. 每次只移动一个清晰职责，避免一次性重写 `AppState`。
2. 先抽取纯函数和数据模型，再迁移有状态逻辑。
3. 服务端事件和 `session/queue` 始终是权威数据源，不引入新的本地镜像协议。
4. 每个阶段必须保持 `flutter analyze`、相关测试和完整测试通过。
5. 新模块不直接依赖 Flutter Widget；协议解析模块保持纯 Dart。
6. 不为解耦而增加抽象层。只有存在明确生产调用方和测试价值时才建立接口。

## 阶段一：会话数据模型与纯事件解析

### 目标

从 `state.dart` 中移出不依赖 `AppState` 生命周期的数据结构和 wire 数据解析。

### 工作项

- 新建 `lib/src/conversation.dart`：
  - `ChatItem`
  - `ChatItemKind`
  - `ChatImage`
  - `AssistantBlock`
- 新建 `lib/src/session_event_parser.dart`：
  - 文本 block 提取
  - 图片 attachment 解析
  - assistant message 内容解析
  - tool result 文本和图片解析
  - queue snapshot 解析
- `state.dart` 继续导出原有公共类型，避免 App 内其他文件大面积改引用。
- 为纯解析函数新增独立测试。

### 完成标准

- `_foldEvent()` 不再直接遍历 content block 构造图片和文本。
- `_decodeQueuedTasks()` 从 `AppState` 移除。
- 协议解析测试覆盖文字、图片、空内容、无效 attachment 和 queue placement 过滤。

## 阶段二：聊天事件折叠器

### 目标

将“已解析事件如何修改聊天列表”的逻辑从连接和会话生命周期中分离。

### 工作项

- 新建 `lib/src/conversation_fold.dart`。
- 建立最小的 `ConversationFoldContext`，只包含折叠实际需要的数据和回调。
- 依次迁移：
  1. `user/message`
  2. `assistant/message` 与 `assistant/chunk`
  3. `tool/call` 与 `tool/result`
  4. `command/run` 与 `command/done`
  5. `todo/write`
- seq 去重、历史缺口、重连和缓存调度仍由 `AppState` 保留。

### 完成标准

- `AppState._foldEvent()` 只负责水位检查、选择目标列表、调用折叠器和保存调度。
- 现有 event fold 测试继续通过，并新增折叠器直接测试。

## 阶段三：下行帧路由

### 目标

将 host/mux frame 的协议分发从 `AppState` 的业务方法中分离，但不改变状态所有权。

### 工作项

- 新建 `lib/src/frame_router.dart`，解析：
  - host session lifecycle
  - session projection
  - approval/question
  - session queue
- router 输出类型化操作或调用窄回调，不持有 `AppState`。
- `AppState` 保留最终状态提交和 `notifyListeners()`。

### 完成标准

- `_onHostFrame()` 和 `_onMuxFrame()` 缩减为路由调用与提交。
- 未知 frame 保持忽略策略。
- frame 测试不依赖 WebSocket。

## 阶段四：连接生命周期控制器

### 目标

在前三阶段稳定后，评估并拆分连接、WebSocket、重连和 resume 恢复逻辑。

### 工作项

- 新建 `SessionConnectionController`，负责：
  - `DshApi` 生命周期
  - mux/host subscription
  - generation 防旧流回写
  - reconnect timer 和退避
  - resume 后替换连接
- 通过回调向 `AppState` 提交 frame 和连接状态。
- 本地缓存、会话状态和聊天列表仍归 `AppState` 或后续领域状态所有。

### 风险门槛

只有在阶段一至三完成且测试稳定后执行。若拆分会增加重复状态或时序不清，则保留现状并记录原因，不强行抽象。

### 完成标准

- 能独立测试连接断开、旧 generation 丢弃和重连调度。
- `AppState.disconnect()` 只协调领域状态清理和 controller 关闭。

## 阶段五：测试与规范整理

### 工作项

- 将超大的测试文件按领域拆分：
  - `session_event_parser_test.dart`
  - `conversation_fold_test.dart`
  - `queue_test.dart`
  - `connection_controller_test.dart`
- 评估逐步启用额外 lint，优先选择低噪音规则。
- 清理无说明的静默异常处理；可选功能失败必须有注释说明为何可以忽略。

## 每阶段验证命令

```bash
export PATH="/home/x/flutter/bin:$PATH"
dart format <changed files>
flutter analyze
flutter test <focused tests>
flutter test
git diff --check
```

## 发布策略

- 每个完成且用户可安全安装的阶段使用一个递增 App 版本发布。
- 纯内部重构也必须完成 APK 构建和 OTA 清单验证，确保产物路径没有回归。
- 发布后验证 APK 大小、SHA-256、公开 manifest 和 Cloudflare 缓存。

## main.dart 后续解耦

聊天展示、会话抽屉、顶部栏、统计栏、模型选择、更新日志、新建会话、OTA 对话框、登录、连接教程、快速开始和问题交互已完成模块化；`lib/main.dart` 已从约 6140 行降至约 990 行，现主要负责应用启动、主页生命周期和页面装配。

## 当前进度

- [x] 任务队列模型和界面模块化（v1.22.7）
- [x] Composer、快捷命令和权限模块化（v1.22.8）
- [x] 阶段一：纯事件解析和会话数据模型已抽取（缓存序列化保留为 AppState 自有持久化接口）
- [x] 阶段二：聊天事件折叠器（用户、助手、工具、命令、待办和回合结束事件）
- [x] 阶段三：下行帧路由（host/mux payload 分类与 AppState 状态提交分离）
- [x] 阶段四：连接 controller 已接管 stream、generation、replace、stop、重连 timer、attempt、稳定重置和 resume
- [x] 阶段五：测试组织、连接生命周期覆盖和静默异常说明

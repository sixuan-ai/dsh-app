# 连接生命周期拆分评估

## 当前职责

`AppState` 当前直接持有 `DshApi`、mux/host stream subscription、stream generation、重连 timer、稳定连接回退 timer 和 reconnect attempt。连接逻辑与本地缓存、会话列表和聊天状态清理交织在 `connect()`、`disconnect()`、`_startStreams()`、`_replaceStreams()`、`resyncAfterResume()` 与 `_scheduleReconnect()` 中。

## 建议模块

新增 `SessionConnectionController`，只负责：

- 持有当前 `DshApi`；
- 打开和替换 mux/host stream；
- generation 防止旧 stream 回调触发重连；
- 指数退避和 jitter；
- resume 时立即替换 stream；
- 停止 stream、timer 和 API。

控制器通过回调输出：

```dart
onMuxFrame(ServerFrame frame)
onHostFrame(ServerFrame frame)
onReconnect()
onConnectionLost(Object? error)
```

`AppState` 继续负责：

- server URL 和登录流程；
- `host.describe` 健康检查；
- 本地 store 生命周期；
- session/chat/queue/projection 状态清理；
- 重连后的 session refresh；
- mux baseline 触发的 tail sync。

## 实施步骤

1. [已完成] 提取不依赖 `AppState` 的退避计算函数并测试初始值、翻倍、上限、负 attempt 和 jitter 边界。
2. [已完成] 建立可注入 stream factory 的 controller，并覆盖 stream 生命周期；timer scheduler 仍由 AppState 暂时持有。
3. [已完成] 用 controller 替换 `_startStreams()` 和 `_replaceStreams()`，保持 `connect()`/`disconnect()` API 不变。
4. 迁移 `resyncAfterResume()` 和 `_scheduleReconnect()`。
5. 增加旧 generation 回调、重复断线、stop 后不重连和 resume 替换 stream 测试。
6. 完整验证后再删除 `AppState` 中的 subscription、timer 和 generation 字段。

## 风险

- mux 和 host 任一 stream 关闭会触发同一次重连，必须防止重复 timer。
- 替换 stream 时旧 subscription 的 `onDone` 不能调度新重连。
- `disconnect()` 必须在同步清理状态前先禁用后续回调。
- controller 不应持有 session/chat 状态，否则会形成第二份状态源。

## 执行决定

阶段三完成后具备安全拆分条件。阶段四采用“先提取退避纯函数，再引入 controller”的两次提交策略，不在一次提交中同时重写连接建立、重连和 AppState 清理。

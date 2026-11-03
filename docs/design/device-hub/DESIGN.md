# xHarness 连接中心 · Liquid Lime

2026-11-03。使用已配置的 Stitch MCP 实际生成及编辑设计，在 Flutter 中重新实现；不把生成的网页代码作为移动端运行依赖。

Stitch 项目 `15171891512700789874`，最终页面信息记录于本机 `.stitch/metadata.json`。原始 MCP 响应与请求保留在本机忽略目录 `.stitch/`；API Key 仅位于用户私有 Codex 配置，未写入仓库或设计文件。

## 视觉

- 深色石墨底 `#101612`、浮起的深绿灰表面、微弱双向阴影与内凹控件槽。
- 主强调色 `#C8FF5F`，用于主操作、路径选中和已确认连接；浅色模式改用深绿文字，保留亮青柠主按钮。
- 当前电脑为独立玻璃卡，局部 12px 背景模糊、细高光边缘和柔和绿色光晕。不使用持续背景动画，不引入 WebView 或网络字体。
- 大圆角、明确文字层级和留白；同时适配浅色主题及 160% 字体。

## 布局与行为

旧长底部弹窗改为完整页面。顶部当前电脑集中呈现名称、实际连接状态、当前路径。未连接显示“离线”或“连接中”，不宣称其他已保存电脑在线。不显示无法证实的延迟、系统版本、最近活跃时间或双向证书认证。

当前电脑已在主卡中展示，不在下方重复占用一行。“我的电脑”计数包括当前电脑；下方优先展示其他可切换电脑，让 x-26 和 OMEN 在常用手机首屏同时可见。新增、切换仍调用既有回调与独立安全存储，不改变设备授权或账户绑定。

连接方式用内凹分段选择，公网未配置时禁用；地址、局域网发现、刷新与备用直连收进可展开设置。底部添加/管理入口保持可见。页面内刷新不关闭页面，避免用户失去检测结果。

Stitch 原始首稿自行补充的 IP、操作系统、活跃时间和协议状态未采用；已调用编辑工具要求纠正，并在 Flutter 里只绑定真实状态字段。

## 文件与检查

- `lib/connection_center.dart`：原生 Flutter 页面和局部视觉组件。
- `lib/main.dart`：页面导航、实际连接状态和当前电脑地址。
- `test/connection_center_test.dart`：电脑与路径切换、未配置公网禁用、离线、设置、帮助。
- `test/connection_center_visual_test.dart`：390×844 深色、浅色和大字体布局；`XHARNESS_RENDER_UI=1 flutter test --no-pub test/connection_center_visual_test.dart` 生成 `build/ui-previews/` PNG。预览使用合成界面数据，不包含设备密钥。
- `stitch-reference.png/html`：Stitch 编辑后的设计参考。实际产品预览以 Flutter 输出为准。

参考：[Codex MCP 配置](https://developers.openai.com/codex/mcp)、[Stitch MCP](https://stitch.withgoogle.com/docs/mcp/setup)、[Stitch SDK](https://github.com/google-labs-code/stitch-sdk)。

## 2.3.0 验收

静态检查通过；全量 247 项测试通过（真实服务凭据测试默认跳过，底层多电脑往返链路已在上一版单独验收）。新增交互检查覆盖当前/其他电脑可见、切换回调、局域网/公网路径、未配置公网禁用、离线和连接中状态、高级地址/发现/刷新/备用路径，以及帮助流程。

390×844 的深色、浅色和 160% 字体渲染检查通过。当前电脑已集中展示在顶部，OMEN 切换行在普通字号首屏可见；添加入口常驻底部。大字体可滚动访问所有功能。生成截图位于 `build/ui-previews/connection-center-{dark,light,large-offline}.png`。

页面还校验当前电脑与实际连接的地址和凭据身份是否一致；新电脑正在探测时不会沿用上一台电脑的“已连接”状态。刷新局域网检测会在当前页面显示进度，不先关闭页面。高级地址文本使用独立 PageStorageKey，避免与展开状态冲突。

Android 版本 2.3.0，安装版本号 2140，沿用原签名并保留多电脑数据格式。没有重启用户电脑上的 DSH 或重置手机配对。

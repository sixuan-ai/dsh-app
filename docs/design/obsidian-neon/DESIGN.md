# xHarness · 黑曜荧光 Obsidian Neon

2026-11-05。依据同目录用户提供的 `reference.html` 完整阅读并以原生 Flutter 实现。没有引入 WebView、网络字体或新依赖；系统中文和等宽字体仅在截图测试中从本机加载。版本为 `2.7.0+149`。

## 视觉与 tokens

| 语义 | Obsidian token |
| --- | --- |
| 背景 / 卡片 / 浮层 / 代码 | `#050706` / `#0F1412` / `#151B18` / `#070A09` |
| 正文 / 次级 / 三级文字 | `#ECF3EE` / `#9DAAA2` / `#5E6B64` |
| 主色 / 浅主色 / 主色上文字 | `#39FF88` / `#9CFFC4` / `#02140A` |
| 信息、链接、公网 / Agent、计划、工具 | `#22D3EE` / `#A78BFA` |
| 警告、待审批 / 危险、错误、diff 删除 | `#FFB547` / `#FF5C7A` |
| 在线、运行中、diff 新增 | 主色 `#39FF88` |
| 分隔线 / 玻璃描边 / 顶部高光 | 白色 8% / 8% / 16% |
| 玻璃渐变填充 / 内高光 | 白色 8% → 4.5% / 低透明度白色 |
| 凸起高光 / 暗阴影 | 白色 3.5%，左上 -5/-5、12px；黑色 85%，右下 7/7、16px |
| 荧光柔光 | 主色 35%，最多 24px |

语义辅助色与玻璃、新拟态字段集中在 `AppPalette`；旧主题根据明暗提供配色，浅色使用白色高光与灰色阴影。`accent2` 在 Obsidian 中为青色。标签使用对应语义色 12% 底色。

默认主题为第一项 `obsidian`，名称“黑曜荧光”、副标题“液态玻璃 · 荧光绿”。`ThemeController.load` 以 `obsidianMigrationV1` 偏好标记完成一次迁移，此后手选旧主题和重启恢复继续生效。浅色主题保留 id `light`，名称“晨雾白”，主色 `#12B866`；旧 `night/eyecare/sakura/neon` 仍可选。

## 组件与页面映射

- `src/ui/glass.dart`：`GlassPanel` 为局部裁剪、18px BackdropFilter、渐变填充、顶边高光和内高光；`AppBackdrop` 在 MaterialApp builder 中提供静态绿/青/紫径向光晕，仅 Obsidian 开启。
- `src/ui/neumorphic.dart`：`NeuSurface` 为双向阴影浮起表面，内部 Material 保留点击水波；`NeuInset` 以渐变和暗/亮边模拟内凹；`NeuSegmented` 使用内凹槽和选中凸起；`NeonButton` 为绿色渐变、柔光和 onAccent 文字。开关由 SwitchTheme 统一。
- `src/theme.dart`：统一按钮、开关、Chip、SegmentedButton、输入、BottomSheet、Dialog、NavigationBar、AppBar、Card、SnackBar、ProgressIndicator。
- 连接入口：局域网与青色公网入口、新拟态卡、荧光配对按钮；登录明确可选。
- 抽屉 / 会话列表：玻璃顶卡、真实连接路径和状态、内凹筛选、浮起会话行、运行与待审批标签；保留分组、折叠、置顶、归档、社区、等级和原回调。
- 对话：低透明绿色用户气泡、玻璃顶栏与输入、代码/工具内凹表面、紫色工具标识、绿色运行状态、红/绿 diff；审批与提问内容为琥珀边玻璃表面，原回答和审批回调保持不变。
- 设置：玻璃账号卡、荧光开关、可复用主题预览卡；设置页与抽屉主题弹窗使用随内容增高的 Wrap 布局，大字号单列，弹窗可滚动。
- 连接中心与宠物饭堂沿用原布局、动画与交互，配色切到统一 palette，玻璃局部模糊更新为 18px。滚动会话行不使用 BackdropFilter。宠物素材未改动。
- `lib/` 的 UI 硬编码 `Color(0x...)` 与 `Colors.*` 全部归入主题语义色，主题文件以外的扫描已无匹配。

## 公网行为与授权边界

1. `state.dart`：`canUsePublicConnection` 恒为 true。账号尚未验证、账号过期、访客均可使用公网。
2. `enterGuestMode` / 退出账号不再因公网地址主动断开；保留电脑入口与配对。配对恢复仍优先探测局域网，不可达时使用该电脑已配置的公网入口。
3. `switchToComputer` 取消 App 登录状态拦截。局域网目标直接使用保存入口，公网目标仍使用旧 Basic 凭据访问目录；异步身份代次检查继续生效。
4. `probeServer` / `connect` 取消 App 登录门槛；电脑地址归属、配对证书固定、配对凭据、HTTP/WS Basic 与凭据身份一致性检查保持原实现。
5. `main.dart`：启动保存凭据直连不再改道局域网；公网/备用直连与电脑切换不再弹出 App 账号页。连接中心取消账号开关与“登录后使用”分支；未配置配对公网地址时仍禁用该公网路径。
6. 连接入口的公网操作进入既有电脑选择/配对流程，不再调用账号回调。默认公网服务继续走原电脑服务认证流程；放开 App 登录不产生默认服务的匿名授权。
7. 账号页、权限说明、连接教程、README、l10n 同步为无需登录即可使用公网、登录可选。没有新增账号云同步协议或改变账号存储格式。
8. composer 原本仅有电脑授权说明，没有发现独立的 App 登录公网拦截；现保留权限选择与发送可用性判断。

## 仓库内服务端只读检查

存在账号/设备授权拦截，全部保持不动：

- `server/registration/dsh-directory.py`：目录登录/解析需要旧 Basic 账号；`/internal/auth` 缺少或错误凭据返回 401，目标电脑未绑定该账号或共享目标无已配电脑返回 403。
- `server/connector/hub.py`：电脑登记/管理需要账号（401），归属其他账号返回 403；公网数据转发校验已配对设备凭据（401），不读取手机 App 的思玄登录状态。
- `server/connector/gateway.js`：配对一次性证明和设备 Basic 校验；错误设备认证返回 401。
- `server/dsh-auth-proxy.js` 与 `server/nginx-dsh.conf.sample`：旧服务、社区/下载的 Basic/cookie 认证仍保留。
- 没有 `ops/` 目录。没有接触、部署或修改任何实际服务器。

## 验收

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub -j 6`：329 项通过、1 项真实服务凭据测试默认跳过。
- 单独启用 PNG 渲染：16 项通过；四张 390×844 深色 PNG 已生成并逐张实际查看，中文与等宽字体、主题选中边框、页面布局正常。
- 浅色与 160% 字体布局检查通过；等级行与标签采用可换行布局，主题选择卡大字号单列。
- `git diff --check` 通过；`lib/`（theme.dart 除外）的硬编码颜色扫描无匹配。
- `test/obsidian_visual_test.dart` 为四个实际页面提供 390×844 的深色、浅色、深色 160%、浅色 160% 共 16 项布局检查，滚动入口和设置页检查后续内容。
- `XHARNESS_RENDER_UI=1 flutter test --no-pub -j 6 test/obsidian_visual_test.dart` 输出 `build/ui-previews/obsidian-{entry,sessions,chat,settings}.png`，使用合成会话、审批与计划状态，不访问真实服务。
- 未 commit、push 或修改 Git 配置；没有改签名、key.properties、发布脚本、凭据、手机、硬件或实际服务器。没有进行 APK 发布或实机验收。

## 改动文件

- `README.md`
- `docs/design/obsidian-neon/DESIGN.md`
- `lib/access_policy.dart`
- `lib/app_account_page.dart`
- `lib/changelog_view.dart`
- `lib/chat_list.dart`
- `lib/chat_view.dart`
- `lib/composer.dart`
- `lib/connection_center.dart`
- `lib/connection_entry_view.dart`
- `lib/connection_guide.dart`
- `lib/home_view.dart`
- `lib/login_view.dart`
- `lib/main.dart`
- `lib/network_diagnostics_page.dart`
- `lib/pet_habitat.dart`
- `lib/pet_page.dart`
- `lib/question_dialog.dart`
- `lib/session_drawer.dart`
- `lib/session_header.dart`
- `lib/session_mode_badge.dart`
- `lib/settings_center.dart`
- `lib/social_page.dart`
- `lib/src/changelog.dart`
- `lib/src/l10n.dart`
- `lib/src/theme.dart`
- `lib/src/ui/glass.dart`
- `lib/src/ui/neumorphic.dart`
- `lib/state.dart`
- `lib/stats_bar.dart`
- `lib/support_page.dart`
- `lib/update_dialogs.dart`
- `pubspec.yaml`
- `test/access_policy_test.dart`
- `test/app_account_page_test.dart`
- `test/app_entry_test.dart`
- `test/composer_test.dart`
- `test/obsidian_visual_test.dart`
- `test/theme_test.dart`

`reference.html` 为用户原有参考文件，未改动。PNG 为忽略目录中的生成产物。

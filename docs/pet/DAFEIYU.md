# 大肥鱼伙伴

所有新领养、历史宠物、成长阶段和匹配赛形象统一为大肥鱼（仓库当前默认的鲸尾女仆）。

## 素材与授权

- 集成仓库：https://github.com/QCYTSN/dsh-dafeiyu
- 固定提交：`084323845ab82b68d5388d5c638bec09d8544a8a`
- 原始动画作者与来源：Copyright (c) 2026 PC2005-cloud，https://github.com/PC2005-cloud/dsh-pet
- 原始素材提交：`549fff2ea33c2acfb16612c76912c6137da4a758`
- 当前默认素材为 MIT 授权；完整许可证随 `assets/pet/dafeiyu/LICENSE.txt` 打包。未使用 legacy 目录。
- `provenance.json` 记录素材来源、帧数、时长、循环方式和产物 SHA-256。

`tool/import_dafeiyu.py --source <固定版本仓库根目录> --output build/dafeiyu-original` 可重建 2.4.0/2.5.0 的原始 WebP 容器。2.5.1 起使用逐帧画质验证后的高质量有损压缩，并共享重复动画；详见 [动画优化记录](ANIMATION_OPTIMIZATION.md)。16 个动作、原画布和完整逻辑时间轴均保留，避免为数千张静帧创建 Flutter 图片缓存。

## 行为

- 默认待机；空闲时每分钟交替伸懒腰与打哈欠。
- 已连接的当前任务运行时：思考、执行命令、搜索、其他工作；有待确认授权/问题时等待。
- 喂白米饭（复用 eat_token 原动画）、玩耍吐泡泡、洗澡伸懒腰；太饿无法玩耍时播放出错反馈。
- 点击上半身摸头、点击下半身挥手；长按提起，松开落地。
- 成长庆祝使用 success；匹配等待使用 thinking。其他状态也可通过 PetSprite.animation 直接调用。
- 原始非循环动画播放一次后恢复当前活动；每个实例只持有解码器和当前帧，切换动画取消旧播放，后台暂停，减少动态效果时显示原始静帧。

## 饭堂页面（2.5.0）

页面已按 Stitch MCP 的生成与精修方案更新，采用青柠玻璃与新拟态布局；1M 已记录上下文自动计入一碗白米饭，手动喂饭作为互动、不扣上下文。详细计量、兼容策略与预览见 [设计与规则](../design/dafeiyu/DESIGN.md)。

## 数据兼容

沿用 `petState`、`petTokenTotals`、`petBonusTokens` 存储键。读取旧物种时只将 `speciesId` 归一为 `dafeiyu`，保留昵称、养成数值、时间、已见成长阶段、PK 积分、Token 历史与奖励池。成长阈值仍为等级 1/3/6/10/15；阶段改为默契称号，始终使用同一形象。同形象对战不再产生物种克制加成。

## 验证

- `flutter test test/pet_test.dart`：旧档迁移、养成、Token、对战、领养与喂食。
- `flutter test test/dafeiyu_animation_test.dart`：逐帧解码全部 16 段动画，核对尺寸、帧时长、循环次数；覆盖一次性动画、快速切换、前后台、减少动态效果。
- `XHARNESS_RENDER_UI=1 flutter test test/dafeiyu_visual_test.dart`：390 × 844 手机页面溢出检查与实际 Flutter 截图。

## 2.4.0 验收（2026-11-03）

- `flutter analyze --no-pub`：无问题。
- 完整测试：252 通过，1 个需显式开启的真实连接测试跳过。
- 全部 3,444 帧已在 Flutter 解码器中逐帧验证；一次性播放、快速切换/销毁与前后台行为通过。
- 390 × 844 实际 Flutter 截图：`build/ui-previews/dafeiyu-adoption.png`、`build/ui-previews/dafeiyu-companion.png`。
- Android arm64：`2.4.0+141`，实际 versionCode `2141`，沿用现有发布签名。
- APK：`build/connector-release/xharness-2.4.0-android.apk`，包含完整 16 段动画和 MIT 许可证；已逐项核对 APK 内素材哈希。
- APK SHA-256：`3d312a0e07b7bcd60989ffe212bb3652ccdb396d608346d7e96260f4cc9559df`。
- 未修改或重启电脑端 DSH 服务，未重置电脑配对、账号或宠物存储。
- 公网发布验证通过：更新清单、实际下载的完整 APK 大小/哈希、升级签名一致性全部通过。
- 更新包：https://dsh.sixuanai.com/releases-public/dsh-app-2.4.0.apk （82,342,665 字节）。

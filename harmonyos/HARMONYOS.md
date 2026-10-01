# HarmonyOS 本地构建

本目录是从当前开发工作区复制出的独立鸿蒙迁移快照，避免覆盖原工作区中尚未提交的修改。

2026-10-01 从 `/home/x/code/sx/dsh_mobile-ohos` 移入 `/home/x/code/sx/dsh_mobile/harmonyos`。父目录是主项目，本目录是鸿蒙版本；两份源码不会自动同步。本目录源码由父仓库维护，签名材料、本地配置和构建缓存不提交。首次检出需将 `ohos/build-profile.json5.example` 复制为 `ohos/build-profile.json5`，再按下文构建。

## 已安装工具

- HarmonyOS Command Line Tools 26.0.0.821：`~/.local/share/harmonyos/26.0.0.821/command-line-tools`
- Flutter OH 3.44.9：`~/flutter-oh`
- DevEco CLI 1.3.0：`devecocli`
- 环境变量：`~/.config/harmonyos/env.sh`
- Flutter OH 命令入口：`flutter-oh`

新终端会自动加载 SDK 环境；当前终端可手动执行：

```bash
source ~/.config/harmonyos/env.sh
```

## 构建

未签名构建（可用于验证编译，不能直接安装到普通真机）：

```bash
./tool/build_harmonyos.sh --unsigned
```

真机调试签名构建：

1. 在鸿蒙手机上启用开发者模式和 USB 调试。
2. 用 USB 连接电脑，并在手机上允许调试授权。
3. 执行：

```bash
./tool/build_harmonyos.sh
```

脚本会调用 `devecocli signature generate`，为当前账号和已连接设备生成调试证书、Profile 与签名配置，然后构建签名 HAP。签名材料只保存在本机，不应提交到版本库。

## 当前平台差异

- 鸿蒙版使用适配过的 `shared_preferences`、`path_provider`、`image_picker`、`package_info_plus` 和 `sqflite` 插件。
- 系统通知插件暂不支持鸿蒙，因此鸿蒙版会跳过本地通知初始化。
- 保存图片到系统相册暂未接入鸿蒙插件；查看、发送图片不受影响。
- Android 应用内 APK 更新逻辑只在 Android 上运行。

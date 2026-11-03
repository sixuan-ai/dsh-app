# xHarness 安装包 Cloudflare 下载链路

2026-11-03。已将公共签名 APK 镜像至现有 Cloudflare 账号中的专用 R2 桶，并接入自定义下载域名和现有 App 下载入口。

## 当前部署

- R2：`xharness-releases`，Standard / APAC。
- 下载域名：`downloads.ainotex.com`，独立于 DSH 业务域名；TLS 最低 1.2。
- 对象前缀：`xharness/`。
- 当前文件：https://downloads.ainotex.com/xharness/dsh-app-2.5.1.apk 。
- 缓存：版本化文件 `public, max-age=31536000, immutable`；已观察到 `CF-Cache-Status: HIT`。
- 签名、版本、安装包内容保持 2.5.1 原有值：73,869,827 字节，SHA-256 `5468eaa37d1bc61d22ea37672e04275dfbb15f09fb627da087b4c9106bf2d5c8`。

下载字节由 R2 / Cloudflare 边缘提供；源站只返回小更新清单和重定向。专用桶存放公共 APK 与健康检查文件。现有 DSH 会话、认证、设备连接继续使用原链路。

## 旧 App 与旧链接兼容

原更新清单地址继续保持：

`https://dsh.sixuanai.com/releases-public/latest.json`

清单中的 `url` 继续指向原版本化公开下载地址，服务器 302 到 Cloudflare；新增 `cdnUrl` 供网站或未来工具直接使用。`latest.json` / `version.json` 继续 `no-store`，不对登录或任务 API 应用下载缓存。

旧 App 会在下载请求中附带账号头。保留原域名入口再跳转至独立域名，可以利用 Dart HTTP 的跨域重定向规则移除认证头。客户端回归测试已验证初始源站有 Basic 头、最终下载端无认证头；部署工具也拒绝使用源站的下级域名作为镜像，以免老客户端继续转发账号头。[Dart 官方重定向说明](https://api.dart.dev/dart-io/HttpClientRequest/followRedirects.html)

只有已上传并验证的版本进入重定向映射，旧版本本地文件仍可用。未列出的公开文件继续由源站提供。

### 源站备用

附加 `?origin=1` 可显式使用源站副本：

`https://dsh.sixuanai.com/releases-public/dsh-app-2.5.1.apk?origin=1`

该参数仅影响公共安装包的下载路径，便于线路诊断或 CDN 故障时手动取回相同文件。`dsh-app-latest.apk` 平时重定向至当前已验证的版本化镜像。

## 后续发布

`tool/publish.sh` 已委托 `tool/publish_release.py`，发布器会自动读取本机的 `server/release-cdn.json`。首次自建时，从 `server/release-cdn.example.json` 复制配置并填写自己的 Cloudflare 账号、域名和 zone ID；实际配置已加入 Git 忽略规则：

1. 校验 APK 身份、真实 versionCode、旧版哈希与覆盖升级签名。
2. 上传 R2，校验对象大小 / ETag，并清除该新 URL 可能存在的负缓存。
3. 从公网完整下载镜像并验证 SHA-256。
4. 保留原源站副本，发布清单。
5. 更新 Nginx 映射，执行 `nginx -t` 与平滑 reload，验证旧入口最终下载内容。

已有版本化 R2 对象只允许验证复用，不能被不同字节覆盖。无效凭据或镜像验证失败会在发布更新清单之前中止。Cloudflare 默认浏览器检查会拒绝部分通用脚本 UA，发布工具使用明确的 `xHarness-Publisher/1.0` 标识；未关闭全站安全设置。实际 App 的 Dart 下载客户端已验证可访问。

发布命令仍为：

```bash
tool/publish.sh --rebuild
```

明确使用 `--no-cdn` 调用 Python 发布器可发布源站版，并清除当前版本及 latest 的 CDN 跳转，其余已验证旧版本的镜像记录保留。

配置分离：Git 中仅提供 `server/release-cdn.example.json` 示例，本机的 `server/release-cdn.json` 保存部署账号 ID、桶名、域名、zone ID 和凭据文件路径。令牌保存在本机 `~/.config/xharness/cloudflare-token`，权限 0600；也支持 `CLOUDFLARE_API_TOKEN` 环境变量。令牌未写入源码、对象、清单或服务器配置。

[Cloudflare R2 自定义域名与缓存说明](https://developers.cloudflare.com/r2/buckets/public-buckets/)、[对象上传 API](https://developers.cloudflare.com/api/resources/r2/subresources/buckets/subresources/objects/methods/upload/)。当前 REST 上传器限制 300 MB，未来更大的文件应改用分段上传。

## 服务端文件与回滚

- 公共 vhost：`/etc/nginx/sites-enabled/dsh-sixuanai`（修改实际指向的文件，保留软链接）。
- 映射：`/etc/nginx/conf.d/xharness-release-cdn.conf`。
- 版本索引：`/var/www/dsh-releases/cdn-index.json`。
- 首次部署备份：`/var/backups/xharness-releases/cdn-20261103-132057/`。

`tool/configure_release_cdn.py` 验证当前清单和源站文件仍匹配后才激活；配置校验或 reload 失败会恢复触及的配置和清单。回归测试验证公开路径限定、已有认证位置不变、版本竞态拒绝和失败回滚。

## 本机下载域名直连

用户额外授权仅将 `downloads.ainotex.com` 直连。原 Meta 模式仍为 rule，已选代理组与原有 3 条规则保持不变，新增最高优先级：

`DOMAIN,downloads.ainotex.com,DIRECT`

规则写入当前订阅的规则增强文件（prepend），订阅自动更新仍会保留：

`/home/x/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/rFgIPtlbul8I.yaml`

同时更新生成配置与服务运行配置，并通过 Mihomo 本地控制接口热加载，未重启代理进程。配置备份位于 `~/.config/xharness/meta-backups/20261103-133102/`。可在 Clash Verge 当前订阅“编辑规则”中删除这一条以恢复原路由；其他规则继续保持原状。

## 实测与验收

同一台电脑当前网络的观测：

| 路径 | 内容 | 时间 / 平均速率 |
|---|---|---|
| 源站 Wi-Fi 直连 | 8 MiB 分段 | 22.87 秒，约 0.37 MB/s |
| Cloudflare Wi-Fi 直连、HIT | 8 MiB 分段 | 8.34 秒，约 1.01 MB/s |
| Cloudflare 经过原 Meta 代理 | 完整 73.9 MB | 373.3 秒，约 0.20 MB/s |
| 仅下载域名 DIRECT 后，通过原下载入口 | 完整 73.9 MB | **35.88 秒，约 2.06 MB/s，HIT** |

最后一项没有指定网络接口或固定 IP，走普通系统下载路径，并验证最终 URL 与全部字节的 SHA-256。样本大小、TCP 热身和线路不同，表格分别记录实际观测，不承诺所有用户网络同速。

客户端完整回归 261 项通过，1 个需显式开启的真实连接测试跳过；静态检查通过。额外 4 项服务端部署/回滚测试和真实 HTTP 跨域凭据隔离测试通过。无需新增 APK 版本或重新安装客户端。

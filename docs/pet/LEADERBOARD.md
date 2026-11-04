# 宠物等级排行榜

榜单以 `PetTokenStore.total()` 排序，包含历史上下文和 PK 奖励池，与宠物页等级一致：`tokens ~/ 1000000 + 1`。形态阈值为 Lv.1/3/6/10/15：初见伙伴、熟悉伙伴、默契伙伴、贴心伙伴、灵魂搭档；当前物种统一为大肥鱼。PK 段位沿用客户端 `petRankForScore`，不参与排序。

## 参与和隐私

- 访客可查看总榜和本周榜；账号身份校验通过后才能上报。登录卡跳转现有账号页。
- 总榜降序排列累计 token；并列时先达到当前值者在前，重复上报不改变达到时间。极端同时间以内部散列稳定排序。
- Top 100 之外仍返回当前用户的实际排名和距上一名的 token 差距；并列差距为 0。
- 默认昵称为脱敏邮箱，如 `z***@qq.com`。设置公开昵称为 1–16 个 Unicode 码点（去除两端空白后），拒绝 Unicode C 类字符（控制、格式等）。宠物名 1–32 字，同样过滤。
- “不参与排行”开启后立即隐藏，客户端停止上报；下一次尝试也会检查服务端偏好，兼容其他设备退出。可在设置中重新开启。隐藏不是删除历史记录。
- 只保存账号 id 的 HMAC-SHA256 标识。密钥需长期稳定、至少 32 字符，由部署环境注入。数据库及返回 JSON 均不保存/返回账号原始 id、邮箱原文、会话 token；排行榜也不返回散列标识。用户自行设置的公开昵称/宠物名是公开文本，勿填写私人信息。
- 会话验证缓存只在进程内保存 token SHA256、散列身份、脱敏昵称，5 分钟过期，最多 4096 项；不记录 Authorization。撤销的会话可能在缓存有效期内仍被接受。

## 周榜

上海时区（`zoneinfo.ZoneInfo('Asia/Shanghai')`）周一 00:00 切换 weekKey（该周周一的 YYYY-MM-DD）。快照每次成功上报更新：新周以此前最后已知总量为基线，首次加入以此次接受值为基线，不将首次导入历史算成本周成长。当前周没有快照时显示增量 0。离线跨周后首次上报的差值归入上报当周，无法准确还原离线期间的逐日成长。重置保留已取得的周增量，后续只计算新的正增量。

## 接口

客户端默认 `https://dsh.sixuanai.com/social/pet`；构建时可用 `--dart-define=PET_BOARD_BASE_URL=https://example.com/social/pet` 覆盖。以下为后端路径，nginx 将 `/social/pet/` 映射为 `/pet/`；后端也接受 `/social/pet/` 便于兼容原反代。

所有响应为 UTF-8 JSON。上报和设置必须带 `Authorization: Bearer <思玄会话>`。GET 不带会话时匿名，有会话时必须验证，不会降级成匿名放行。

- `GET /pet/board?scope=all|week&limit=100`，limit 范围 1–100。
- `POST /pet/me`：`{"petName":"大肥鱼","species":"dafeiyu","stage":"初见伙伴","tokens":1200000,"pkScore":1000}`。服务端重新计算等级、形态和物种，不信任客户端 stage/level。可额外传 `"reset":true` 明确主动重置并允许总量降低；当前客户端没有新增重置成长功能。成功返回 `{"ok":true,"tokens":1200000,"level":2,"stage":"初见伙伴","optedOut":false}`。
- `PATCH /pet/me`：`{"nickname":"小鱼","optedOut":true}`，两字段均可省略，保留原值。返回 `{"ok":true,"nickname":"小鱼","optedOut":true}`。

GET 示例：

```json
{
  "scope": "all",
  "weekKey": "2026-11-02",
  "items": [{"rank":1,"nickname":"z***@qq.com","petName":"大肥鱼","species":"dafeiyu","stage":"熟悉伙伴","tokens":2200000,"pkScore":1200,"level":3,"score":2200000,"gap":0}],
  "me": {"rank":128,"nickname":"小鱼","petName":"大肥鱼","species":"dafeiyu","stage":"初见伙伴","tokens":1000000,"pkScore":1000,"level":2,"score":1000000,"gap":200000,"optedOut":false}
}
```

周榜 score 为本周增量，tokens 始终为累计总量。匿名响应没有 me。未上报/已退出的 me 返回 `rank:null,nickname,optedOut`，不返回个人标识。错误为 `{"error":"说明"}`；400 参数无效、401 会话无效、413 请求超过 4096 字节、429 上报太频繁、503 校验服务不可用或尚未配置 HMAC 密钥。

账号验证使用 `POST https://accounts.sixuanai.com/api/currentUser`，JSON `{}` 和 Bearer 头，8 秒超时。`PET_ACCOUNTS_URL` 可覆盖完整地址。实际返回（2026-11-05 核对线上 sixuan-accounts）为直接的 user 对象 `{"name","email","display_name","status","is_admin","info"}`，没有数字 id；以规范化（去空白、小写）的已验证邮箱作为账号键，仅以 HMAC 散列入库。也兼容 `{"user":{...}}` 包装。部署前须核对自建账号服务格式，格式错误返回 503；认证边界是 `pet_board.validate_account(token)`，测试注入假实现。绝不以客户端邮箱代替服务端身份。

## 数据与反作弊

扩展现有 SQLite，无第三方依赖：

- `pet_board`：user_key 主键、nickname、opted_out、pet_name、species、stage、tokens、pk_score、reached_at、updated_at；额外 last_report 用于限频、suspicious 统计截断次数。
- `pet_board_snapshots`：user_key/week_key 联合主键，start_tokens、last_tokens、reached_at（周榜并列排序）。
- `pet_board_deltas`：散列 user_key、time、delta，用于滚动一小时正增量限制；上报时删除超过一小时的记录。

普通上报总量降低时忽略下降，保留旧值；显式 reset 才允许降低并更新达到时间。每账号成功上报间隔至少 20 秒；设置不受此限制，以便随时退出。`PET_MAX_DELTA` 单次增量上限与 `PET_MAX_HOURLY` 滚动一小时增量上限默认均为 30000000，首次上报也受限；超限截断并增加 suspicious。正增量记录持久化，进程重启不会清空每小时额度。只有最终接受的 token 才用于排名。

客户端在宠物页打开时尝试同步；成长变化后 30 秒尾沿去抖；前台恢复最多每 10 分钟一次；发送还遵守最短 20 秒间隔。请求串行，失败一分钟后静默重试，离开账号或退出排行会取消待执行任务。已发出的请求无法撤回，但后续任务不会带旧会话。

客户端本地数据不是可信证明：伪造 token、PK 分数、主动重置仍有可能，无法防止分散持续刷量或多账号。PK 分数仅做范围校验；应将此榜作为娱乐功能。首次历史值过大时可能需多次同步才能达到本地等级（服务端截断期间页面值可能暂有差异）。如需可信竞技排行，须由可信任务服务签发成长流水，而非提高客户端权限。

## nginx 样例（只供人工部署）

完整上下文见 `server/nginx-dsh.conf.sample`，所用 `dsh_api` zone 见已有 `nginx-dsh-ratelimit.conf.sample`，放在 http 上下文。最长前缀确保宠物路由不进入社区的 Basic 认证：

```nginx
location ^~ /social/pet/ {
    auth_basic off;
    limit_req zone=dsh_api burst=20 nodelay;
    limit_req_status 429;
    client_max_body_size 4k;
    proxy_pass http://127.0.0.1:9981/pet/;
    proxy_set_header Authorization $http_authorization;
    proxy_set_header Host $host;
    proxy_read_timeout 15s;
    add_header Cache-Control "no-store" always;
}
```

此为 IP 级反滥用限流，服务端另有账号级上报限频。社区其余路由保持既有认证。服务端只监听回环地址，公开入口必须 HTTPS；不在访问日志中添加 Authorization。

## 人工部署与回滚清单

本次实现没有执行以下任何线上操作。

1. 备份现有服务代码、SQLite（使用 SQLite 在线 backup 或停服复制）和 nginx 配置；确认磁盘空间。
2. 设置稳定的随机 `PET_BOARD_HMAC_KEY`（至少 32 字符），安全注入服务环境；不要提交密钥。可设置 PET_ACCOUNTS_URL、PET_MAX_DELTA、PET_MAX_HOURLY。`SOCIAL_DB_PATH` 默认沿用 `/opt/dsh-social/social.db`。
3. 在隔离环境核对 currentUser 返回格式和无效会话行为；确认 Python 有上海时区数据；执行下列测试。若配置上限，使用正整数。
4. 将 `social-server.py` 与同目录的 `pet_board.py` 一起安装；重启社区服务。表在首次宠物请求时以 CREATE IF NOT EXISTS 创建，旧表无破坏性迁移。
5. 人工合并 nginx 样例，运行 nginx 配置检查后再 reload；核验匿名榜单无 Basic 挑战、写入无 Bearer 返回 401、账号服务不可用返回 503、社区原认证仍生效。
6. 先用测试账号验证排名、退出隐藏、周榜，再发布相应客户端。监控错误率和 SQLite suspicious 计数（不要采集原始身份/会话）。
7. 回滚：先关闭/移除新增 nginx 路由以停止新榜单流量，再恢复旧服务代码及原 nginx 配置并人工检查/reload。新增表可保留，不影响旧代码；确需恢复数据库时先停止写入并备份回滚前数据库。保持 HMAC 密钥，避免之后启用产生重复身份。密钥轮换无法从散列反推身份，需要专门迁移或清空榜单并重新加入。

本地验证命令（并发不超过 6）：

```bash
export PATH=/home/x/flutter/bin:$PATH
flutter analyze
flutter test -j 6
python3 -m unittest discover -s server/tests -p 'test_*.py'
python3 -m unittest discover -s server/registration -p 'test_*.py'
python3 -m unittest discover -s server/connector -p 'test_*.py'
node server/tests/dsh-auth-proxy-auth.cjs
XHARNESS_RENDER_UI=1 flutter test -j 6 test/pet_board_test.dart
```

连接器既有测试的二维码用例需要其原有 `server/connector/requirements.txt` 中的 qrcode==8.2，应在连接器隔离环境中运行；宠物榜和社区服务没有新增 Python 依赖。

预览输出 `build/ui-previews/pet-board-{all,guest}.png`，390×844，使用合成数据。测试同时覆盖浅色主题和 160% 字体，领奖台在大字时切为纵向布局。

## 本次本地验收（2026-11-05）

- `flutter analyze`：No issues found。
- `flutter test -j 6`：348 通过，1 个既有真实服务凭据用例默认跳过。
- 宠物榜服务端 unittest：12 通过；注册服务既有 unittest：3 通过。
- 连接器既有 unittest：21 通过（使用 `/tmp/xharness-relay-tests-venv/bin/python`，其已有 qrcode 依赖；系统 Python 未安装该可选依赖时二维码用例失败）。
- 既有认证代理回归：12 通过。
- `XHARNESS_RENDER_UI=1 flutter test --no-pub -j 6 test/pet_board_test.dart`：19 通过；两张 390×844 深色 PNG 已生成并实际查看；包含浅色与 160% 字体布局验证。
- `git diff --check` 通过；未改版本号或 changelog，未 commit/push、部署、SSH、操作手机或读取指定凭据。

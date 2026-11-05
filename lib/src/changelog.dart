/// Bundled release notes shown in the in-app changelog.
library;

/// One change line in a release.
class ChangelogChange {
  const ChangelogChange(this.type, this.text);

  final ChangelogChangeType type;
  final String text;
}

enum ChangelogChangeType { feature, improvement, fix }

/// One released version.
class ChangelogRelease {
  const ChangelogRelease({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<ChangelogChange> changes;
}

/// App version mirrored from pubspec.yaml (versionName); bump both together.
const kAppVersion = '2.7.3';

/// Release notes, newest first.
const kChangelog = [
  ChangelogRelease(
    version: '2.7.3',
    date: '2026-11-05',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新建会话可直接浏览电脑文件夹选择工作区，支持新建文件夹，已注册工作区一目了然',
      ),
      ChangelogChange(ChangelogChangeType.fix, '修复手机端远程目录浏览接口失效的问题'),
    ],
  ),
  ChangelogRelease(
    version: '2.7.2',
    date: '2026-11-05',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '宠物排行榜与侧边栏改用大肥鱼头像和爪印图标，前三名按奖牌色描边',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.7.1',
    date: '2026-11-05',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '宠物等级排行榜：登录思玄账号即可上榜，支持总榜与本周榜、我的排名、公开昵称和不参与排行',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '宠物页与侧边栏新增排行榜入口，访客也可查看榜单',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.7.0',
    date: '2026-11-05',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '统一黑曜荧光设计：液态玻璃浮层、新拟态控件与荧光绿主色',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '未登录也可使用公网连接，登录可选用于账号同步与注册，电脑端配对和授权保持不变',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.6.2',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '明确未登录可完整使用局域网、多电脑、任务与模型选择，App 不按登录状态限制使用次数或电脑数量',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '新增“功能与权限”说明，登录后增加公网连接，操作权限继续由电脑端授权',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '未登录切换旧账号公网电脑时先引导登录，避免提前访问公网目录；取消过期账号选择响应',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.6.1',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        'App 登录改为邮箱和密码直接登录，不再重复发送验证码，避免注册后立即登录触发发信冷却',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '注册与找回密码保留邮箱验证码；密码登录支持错误重试与保持登录',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '旧 DSH 账号退出时也保留电脑和配对记录，统一返回局域网模式',
      ),
      ChangelogChange(ChangelogChangeType.fix, '调整邮箱输入框的微信输入法兼容，避免只显示候选条而无法输入'),
    ],
  ),
  ChangelogRelease(
    version: '2.6.0',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增可跳过登录的欢迎页，不登录即可进入应用，通过局域网配对并控制电脑',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '复用思玄邮箱认证，支持 App 内注册、密码与邮件验证码登录、找回密码',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '登录后可切换局域网与已配置的公网入口；退出账号保留电脑配对，并回到局域网模式',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '更新荧光绿与玻璃质感账号界面，适配明暗主题、小屏和大字体',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.5.3',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '权限快捷入口直接打开权限选择面板，不再只填入 /permission 指令',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复新版 DSH 命令接口参数不兼容导致完全访问切换失败，同时恢复服务器快捷命令目录加载',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '底部与侧边栏共用权限选择流程，标记当前权限，并避免确认期间切换会话后误改其他会话',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.5.2',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复脚本完成后工具卡片仍显示运行中：保留跨页完成结果，并补齐订阅建立期间遗漏的进度',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '恢复当前模型与推理强度显示，实时同步电脑端选择，避免切换会话或电脑后旧请求覆盖新模型',
      ),
      ChangelogChange(ChangelogChangeType.fix, '修复子代理状态弹窗与顶部状态未随任务完成及时刷新'),
    ],
  ),
  ChangelogRelease(
    version: '2.5.1',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '大肥鱼动画资源减小约8.5MB：共享重复动作，采用逐帧画质验证后的高质量压缩',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '保留16个动作、原分辨率与完整播放时长，动画继续随包提供，离线可用',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.5.0',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        'Stitch 设计的大肥鱼饭堂：青柠玻璃、新拟态层次，适配深浅主题与大字体',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '1M 上下文是一碗白米饭：累计自动吃饭、成长，展示下一碗进度；手动喂饭作为陪伴互动',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '饭碗仅统计已记录上下文，训练奖励保留原有等级；旧养成、昵称和动画继续保留',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '自动吃饭保存去重进度，修复多会话并发统计丢失及减少动态效果时互动状态不结束的问题',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.4.0',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '宠物统一为大肥鱼：接入开源仓库默认鲸尾女仆形象与全部 16 段原始动画',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '支持摸头、挥手、长按提起、吃 Token 和吐泡泡，任务状态联动思考、工作与等待',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '旧宠物自动迁移并保留昵称、养成和 Token 历史；成长改为默契称号，始终使用同一形象',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '动画按需解码、后台暂停，兼容减少动态效果设置',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.3.0',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '全新连接中心：液态玻璃与新拟态层次，荧光绿重点色，适配深浅主题',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '当前电脑单独展示，其他电脑集中切换，添加入口常驻底部',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '连接状态与离线状态明确区分，未配置公网时禁用对应入口，保留地址与发现功能',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.2.2',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '多电脑快速切换或退出时，取消尚未完成的旧选择，防止迟到响应恢复旧电脑',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '保留 2.2.1 的多电脑列表与旧版 x-26 配对迁移，原 OMEN 账号入口继续可用',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.2.1',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '支持保存多台配对电脑，在连接中心切换各自的工作区与会话',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '配对新电脑后继续显示原账号电脑，升级保留现有 x-26 配对',
      ),
      ChangelogChange(ChangelogChangeType.fix, '切换电脑分别使用对应凭据，忘记一台电脑不会移除其他电脑'),
    ],
  ),
  ChangelogRelease(
    version: '2.2.0',
    date: '2026-11-03',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增电脑配对：导入一次性二维码，使用独立设备凭据连接自己的 DSH',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '已配对电脑局域网优先，支持已注册公网入口回退，保留同一任务视图',
      ),
      ChangelogChange(ChangelogChangeType.fix, '配对密钥存入系统安全存储，设备凭据不用于官网账号服务'),
    ],
  ),
  ChangelogRelease(
    version: '2.1.5',
    date: '2026-11-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '工具卡片里的 edit / write 现在只显示改动的行（和网页一致），不再是一整段参数',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.1.4',
    date: '2026-11-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        'AI 日报与 AI 知识学习的内容源随服务迁移到广州节点，旧域名下线后仍能正常加载',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.1.3',
    date: '2026-11-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '网络恢复后自动重连会卡在“正在恢复”：现在 15 秒内自愈，不再需要手动点重试或重启',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.1.2',
    date: '2026-11-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '在网页或另一台设备上答完审批/提问后，手机端的弹窗会自动关闭，不再卡到必须重启',
      ),
    ],
  ),
  ChangelogRelease(
    version: '2.1.1',
    date: '2026-11-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '一个账号可绑定多台电脑：登录后自动连默认电脑，也能在「连接中心」里切换',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '默认服务器换到广州节点 dsh.sixuanai.com，连接延迟更低',
      ),
      ChangelogChange(ChangelogChangeType.improvement, '聊天缓存按电脑隔离，换电脑后不会串会话'),
      ChangelogChange(ChangelogChangeType.fix, '退出登录后立即回到账号登录页，并清除上个账号的电脑列表'),
    ],
  ),
  ChangelogRelease(
    version: '1.35.7',
    date: '2026-09-12',
    changes: [
      ChangelogChange(ChangelogChangeType.fix, '退出登录后立即回到账号登录页，并清除上个账号的电脑列表'),
    ],
  ),
  ChangelogRelease(
    version: '1.35.6',
    date: '2026-09-12',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '登录页简化为账号密码登录，电脑与网络选择统一放在连接设置',
      ),
      ChangelogChange(ChangelogChangeType.feature, '同一账号连接多台电脑，在连接与安全中随时切换'),
      ChangelogChange(ChangelogChangeType.fix, '邮箱登录与电脑认证统一，重新验证邮箱改密码保留电脑绑定'),
    ],
  ),
  ChangelogRelease(
    version: '1.35.5',
    date: '2026-09-12',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新用户注册:App 里用任意邮箱收验证码建账号(验证码经企业邮箱发出),注册页加入口与流程说明',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '连接更强健:连接本机 DSH 时不再需要手动填 dsh 令牌,代理会自动完成换取,重启 DSH 也不用改手机',
      ),
      ChangelogChange(ChangelogChangeType.fix, '注册接口加 App 凭据头,防止公网扫描滥用验证码发信'),
    ],
  ),
  ChangelogRelease(
    version: '1.35.3',
    date: '2026-09-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复 Agent 提问/审批在手机上不弹窗:新版服务器把提问与审批改为 \$events 流的瀑布事件(waterfall),App 已适配并按新通道回传答案',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.35.2',
    date: '2026-09-02',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复无法加载更早的历史消息:适配新版服务器协议,历史翻页改用一元接口调用',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.35.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复应用内更新下载可能卡在 0% 的问题:下载新增连接超时与停滞检测,无响应会自动重试一次,网络慢时也有提示',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.35.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增「炫彩霓光」主题:深邃夜空底 + 霓虹青→品红渐变强调色与发光控件,赛博霓虹风格',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.34.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复 Android 真机上本地数据库打开失败的问题(WAL 设置语句不兼容),自 1.31.2 起会话缓存实际未生效;修复后冷启动秒开缓存恢复、工作区列表正常显示',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.34.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '会话分组与网页端完全对齐:抽屉直接使用服务器工作区注册表(标题与排序),旧会话按目录自动归入对应工作区;自定义目录新建会话时会自动注册为工作区,不再产生网页端的「未分组」',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.33.2',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复 App 新建会话后网页端显示为「未分组」的问题:创建时自动匹配服务器工作区并同步 workspace 归属',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.33.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复「更多功能」面板在部分屏幕比例下内容溢出的问题,现在可以滚动查看全部功能',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.33.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '设置新增「开发者模式」开关:默认关闭、界面更简洁,开启后显示开发者工具入口(状态/日志/重启),开关状态自动记住',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.32.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '本地缓存分块存储:长会话保存时只重写有变化的部分,大幅减少磁盘写入量;旧缓存自动迁移到新格式,无需重新下载',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.32.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增开发者工具：实时查看电脑上 DSH 的运行状态（版本/内存/CPU/运行时长）、请求与进程日志（3 秒自动刷新），并支持一键重启 DSH',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.31.2',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '优化本地 SQLite 存储：长会话缓存序列化移入后台线程，消除保存时的界面卡顿；数据库启用 WAL 提升并发读写性能',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.31.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '自动搜索可靠性：mDNS 失败或超时时自动回退到局域网端口扫描（部分手机/路由器会过滤组播），并修复超时卡死',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.31.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '连接中心新增“自动搜索局域网设备”：通过 mDNS 自动发现电脑上的 DSH，点击即可连接，无需手动输入地址',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.30.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '支持局域网直连电脑：连接中心可填写电脑局域网地址并检测（电脑端 DSH 需开启局域网监听，见连接教程）',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.29.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复已完成任务仍显示在队列列表的问题：重新订阅时重置队列、插队消息转为正式消息时自动移除',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.29.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '设置中心新增 DSH 更新：对比电脑上安装的 DSH 版本与 npm 最新版，显示更新说明与升级命令',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.28.1',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '顶部栏点击会话标题可查看完整会话名（长按也有提示），不再被截断后看不到',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.28.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '会话顶部与列表显示当前模式：目标模式（/goal）/ 计划模式（/plan）/ 自动模式，状态随会话实时更新',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.27.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        'API 余额改为通过电脑上的 DSH 直接查询：无需再填写密钥，密钥始终留在电脑上',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.26.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '设置中心新增 API 余额：填入 DeepSeek 密钥即可查看官方余额（可用总额/赠金/充值），密钥仅保存在本机',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.25.0',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增设置中心：可切换语言（跟随系统 / 简体中文 / English）、切换主题、以及连接与帮助入口',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增用户反馈页面：选择类型并描述问题，提交后同步到服务器',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增联系客服页面：聚合站内反馈、社区、教程与更新日志入口',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.8',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复连接中心线路状态显示错误：切换深圳后仍显示香港的问题（状态改为依据实际连接地址判定）',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.7',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '连接中心根据当前线路动态显示切换目标：深圳状态显示“切换回香港服务器”，香港状态显示“切换到深圳服务器”',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.6',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '连接中心新增当前连接横幅、正在使用状态和明确的切换按钮文案，避免误以为深圳线路尚未启用',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.5',
    date: '2026-08-25',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '深圳直连切换到 dsh.qxrobot.com：保持同一深圳服务器和 DSH 后端，绕开 sz.ainotex.com 的 TLS/SNI 重置问题',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.4',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '深圳直连失败后增加 Android 原生 OkHttp 对照探测，明确区分 Dart TLS 问题与手机/运营商链路问题，不改变现有消息和 WebSocket 网络层',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.3',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '升级至 Flutter 3.47.1 与 Dart 3.13.1，使用新版 Android 网络引擎重新构建，用于验证深圳线路 TLS 重置问题',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.2',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复深圳直连被运营商 RST 重置（errno 104）导致切换失败：新增 9443 备用端口，443 被掐断时自动切换，绕开未备案域名的 443 抽样封锁',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.1',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复移动网络下切换深圳直连偶发"切换失败"：连接探测超时从 3 秒放宽到 10 秒并自动重试一次，失败时显示具体原因',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.24.0',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '连接中心新增深圳直连线路：不经过 Cloudflare，国内延迟从约 500ms 降至 100ms 内',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.23.1',
    date: '2026-08-24',
    changes: [
      ChangelogChange(ChangelogChangeType.fix, '目录浏览在电脑未开启远程浏览能力时显示明确的中文引导说明'),
    ],
  ),
  ChangelogRelease(
    version: '1.23.0',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增目录浏览页：树形查看电脑上的目录，支持隐藏文件开关与路径复制',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增网络诊断页：8 次探测统计最小/平均/最大延迟、抖动和成功率',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.29',
    date: '2026-08-24',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement, '界面打磨：聊天空状态增加品牌图标引导'),
    ],
  ),
  ChangelogRelease(
    version: '1.22.28',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：社区动态卡片阴影与等级分享描边，统一社交页质感',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.27',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：选中主题卡片增加辉光、宠物主页徽章描边与操作卡片阴影',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.26',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：思考过程展开折叠平滑动画、当前版本卡片品牌高亮、打字指示器配色统一',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.25',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：连接教程步骤序号渐变高亮、命令块代码质感、更多功能网格图标着色',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.24',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：连接中心改为卡片式状态展示，新建会话工作区选中样式统一',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.23',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '登录页密码支持显示/隐藏切换，主按钮增加品牌辉光',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.22',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：问题选项选中样式统一、完全访问权限改用警示色、输入框聚焦描边',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.21',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：任务队列空状态与插队任务高亮、当前模型选中样式统一',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.20',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：图片卡片描边与阴影、沉浸式图片预览、空会话品牌光晕、工具运行状态呼吸条',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.19',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面打磨：输入框聚焦高亮、用户气泡高光描边、选中会话指示条、时间胶囊与 Markdown 排版优化',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.18',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '主页按 Header、统计、聊天和输入区分离状态监听，减少无关区域重建',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.17',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '将审批、提问、升级提示与模型加载移出主页构建过程，提升状态更新稳定性',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.16',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '流式回答时仅重建内容发生变化的聊天项，减少长会话 Markdown 重复解析',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.15',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '将图片方向修正与 JPEG 压缩移出界面线程，降低添加大图时的卡顿',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.14',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '减少流式消息期间重复滚动调度，并优化会话抽屉列表投影和资料刷新',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.13',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '连接中心拆分为独立模块，完成 main.dart 页面级解耦收尾',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.12',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '继续拆分快速开始、空会话欢迎页和问题交互弹窗，main.dart 收敛为主页装配层',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.11',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '聊天消息、工具结果和图片预览拆分为独立模块，继续缩小主页面',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.10',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '会话事件折叠、下行帧路由和连接生命周期完成模块化解耦',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '连接重试、恢复和旧流失效逻辑增加独立测试保障',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.9',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '会话事件解析与聊天数据模型拆分为可独立测试的纯 Dart 模块',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '新增完整核心代码解耦计划文档，按阶段推进后续重构',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.8',
    date: '2026-08-24',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '会话输入、快捷命令和权限组件拆分为独立模块，降低主页面耦合',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.7',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '任务队列拆分为独立模块，降低主页面和状态层耦合',
      ),
      ChangelogChange(ChangelogChangeType.fix, '断开连接时清理旧队列，避免切换服务器后残留任务'),
    ],
  ),
  ChangelogRelease(
    version: '1.22.6',
    date: '2026-08-23',
    changes: [
      ChangelogChange(ChangelogChangeType.feature, '排队任务支持编辑和删除，修改通过服务端队列实时同步'),
      ChangelogChange(ChangelogChangeType.improvement, '删除排队任务前增加确认提示，避免误操作'),
    ],
  ),
  ChangelogRelease(
    version: '1.22.5',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '任务队列入口移至顶部操作栏，输入框获得更多空间',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.4',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        'AI 工作中可以继续输入任务，任务会自动排队并按顺序执行',
      ),
      ChangelogChange(ChangelogChangeType.feature, '新增任务队列展示区域，可查看排队数量和待处理内容'),
    ],
  ),
  ChangelogRelease(
    version: '1.22.3',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '权限设置已移入快捷命令弹窗，输入框获得更大的文字空间',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '启动时优先显示本地缓存会话，服务器列表在后台刷新，不再阻塞首屏',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.2',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '模型服务并发上限等代理错误只显示一次，失败后不再残留“正在生成”占位',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '代理错误卡片新增“重试”按钮，并将并发/限流错误翻译为可读中文提示',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.1',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '锁屏期间产生的大量新消息会先显示最新进度，再在后台补齐中间历史',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '补齐中间历史时不打断当前浏览，也不会覆盖本地已缓存内容',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.22.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '锁屏恢复后立即重建实时连接，并优先同步当前会话的最新进度',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '长对话恢复时不再清空本地历史，只拉取并合并最新几条消息',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复重连后重复拉取历史、覆盖本地缓存以及审批提问重复出现的问题',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.21.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '已加载的历史对话完整保存到手机本地，再次打开时优先本地显示',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '加载更多仅从本地历史缺口继续请求服务器，减少重复下载和等待时间',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.20.1',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '图片全屏预览页新增下载按钮，可直接保存到手机系统相册',
      ),
      ChangelogChange(ChangelogChangeType.improvement, '增加保存进度、成功提示以及相册权限失败指引'),
    ],
  ),
  ChangelogRelease(
    version: '1.20.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '会话右上角新增子代理状态入口，运行时显示绿色标记和正在工作的子代理数量',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '子代理面板可查看任务名称、工作状态、会话类型以及是否包含下级代理',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.19.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '输入框新增完全访问快捷键，可直接切换当前会话的工作区写入与完全访问模式',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复代理和子代理创建的内部会话错误出现在侧边栏工作区会话列表的问题',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.18.1',
    date: '2026-08-23',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement, '“AI 新闻”正式更名为“AI 日报”'),
    ],
  ),
  ChangelogRelease(
    version: '1.18.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        'AI 新闻按北京时间10点切分新闻日，默认显示最近已结束的新闻日',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '左右滑动每次切换前一天，支持连续查看更早历史新闻，并扩大模型公司覆盖范围',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.17.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        'AI 新闻支持左右滑动切换日期，每个日期页展示当天最新和前一天新闻回顾',
      ),
      ChangelogChange(ChangelogChangeType.improvement, '新增日期标题、回到今天和无新闻日期提示'),
    ],
  ),
  ChangelogRelease(
    version: '1.16.1',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        'AI 新闻和知识学习改为由 xHarness 网站统一整理发布，App 不再直接请求第三方新闻源',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        'AI 内容支持网站统一版本、刷新和本地缓存，断网时继续阅读上次成功同步的内容',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.15.2',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '右上角三点菜单新增“检查更新”入口，可在会话页面快速检查并安装新版本',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.15.1',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复检查更新时重复弹窗：更新检查、安装权限和下载流程现在只会按顺序显示一次',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.15.0',
    date: '2026-08-23',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '图片结果现在直接显示在对话流中，工具卡片保留调用详情且不再重复显示图片',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '生成图片增加“图片结果”标题和来源标识，点击即可全屏预览',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.14.2',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复生成图片不显示：DSH 工具结果中的图片附件此前被折叠为占位文本，现在保留附件引用并在工具卡片中显示',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '工具卡片展开即可查看生成图片，历史会话同样恢复，仍通过 session.attachment 鉴权加载',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.14.1',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '产品名称统一为 xHarness，应用名称、界面、官网和文档不再使用旧拼写',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.14.0',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '生成图片回显：支持显示 DSH assistant 消息中的持久图片附件，复用网页端 session.attachment 鉴权接口',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '生成图片支持历史恢复、点击全屏预览、缩放与加载失败重试，无需修改 DSH',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.13.0',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '连接中心：无需退出登录即可检测本地电脑，并在远程连接与本地连接之间一键切换',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '本地检测使用真实 DSH 健康检查，失败时保持原连接；回到 App 前台后会自动重新检测',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.12.2',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '统一连接术语为“远程连接/本地连接”，避免把本地网络误解为只能在家使用',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.12.1',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '面向普通用户重构连接文案：使用“本地连接/远程连接”，增加适用场景、安全边界、友好错误提示和风险提醒',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '官网新增连接方式说明与安全基线，不再要求普通用户理解 FRP、反向代理等技术术语',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.12.0',
    date: '2026-08-22',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '连接引导:登录页支持远程与本地连接选择，提供电脑端分步配置教程、命令复制和首次使用快速上手弹窗',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '记住上次连接方式和局域网地址，并可从“更多功能”随时重新查看连接教程',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.11.0',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '图片消息:支持相册选择和拍照、最多 4 张预览与移除、自动压缩、图片加文字发送、历史图片恢复、失败重试和全屏缩放查看',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.11',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '会话管理:抽屉新增 会话/运行中/置顶/已归档 筛选;支持本地持久化置顶和服务端持久化归档,置顶会话优先排序',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.10',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '宠物视觉升级:使用原创 Q 版矢量精灵立绘替换 emoji,五大家族各有配色与特征,高阶形态增加光环/翅膀/角/尾巴和闪光特效,蛋快孵化时显示裂纹',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.9',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '训练家匹配赛:人机匹配对战(宝可梦风昵称/段位/胜率),新增段位系统 青铜🥉→王者👑,胜负影响段位分(胜+25/败-15)',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.8',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '宠物对战:挑战野生宠物,回合制战报+血条动画,五物种循环克制;胜者从主人处赢取 0.2M tokens 成长值(输了会被扣,历史对话 tokens 不受影响)',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.7',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '宠物家族更名宝可梦/洛克王国风格:哈灵/雷光猫/苍月狼/焚天炎龙/九天凤凰,每个形态都有专属名字(闪电喵→疾电猫→雷纹虎→雷霆狮皇…)',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.6',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '神秘蛋领养:随机抽取物种(灵宠/灵猫/神犬/神龙/凤凰五条进化链),孵化瞬间揭晓物种,名片显示物种标签',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.5',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '宠物进化:等级提升自动进化形态 🥚蛋蛋→🐥幼崽→🐱小猫→🐯猛虎→🐉神兽,进化时有庆祝弹窗;蛋快孵化时会提前破壳',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.4',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '启用正式发行签名(替换 debug 密钥),为后续上架应用商店做准备。注意:签名更换后旧版无法覆盖安装,需先卸载再装',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.3',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复提问/审批弹窗在网页端回答后不自动消失:现在另一端处理完会实时联动关闭,不用再重启 App',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.2',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '侧边栏瘦身:主题/宠物/权限模式/更新/日志/退出收进「更多功能」九宫格,会话列表拿回全部高度;更新提示红点透传到入口上',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.1',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '宠物成长改为按对话 tokens 计算:每命中 1M tokens 升一级,喂食/玩耍/洗澡只管饱腹/心情/清洁',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复浅色主题下发送按钮隐形(点原位置仍可发出):HyperOS 上 Ink+渐变不绘制,已换成 Container 实现',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.10.0',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新增宠物功能:领养一只专属小可爱,喂食/玩耍/洗澡照顾它,状态会随时间变化,还有成长等级(抽屉 → 宠物)',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '抽屉新增「权限模式」入口:一键切换工作区写入/完全访问,完全访问带风险确认,不用再手敲 /permission 命令',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复审批/提问弹窗可被返回键误关:关闭后不再消失,未回答时自动重新弹出,不再卡住对话',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复快捷命令面板显示不全:命令较多时(如 /permission)可上下滑动完整浏览',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.9.2',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '回答提问/审批时若已失效(如 dsh 服务重启),现在会明确提示"回答未送达",不再静默吞掉',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.9.1',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '升级弹窗全新设计:渐变头部+更新日志卡片+全宽渐变按钮;下载进度改为大圆环+实时网速,失败可一键重试',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.9.0',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '多实例登录:登录时按用户名自动连接到你的 dsh 实例(本机/Mac),无需关心域名',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '登录后记住所属实例,启动直连不再绕路;社交与更新仍走主域,不受实例切换影响',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.8.2',
    date: '2026-08-21',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '链路提速:历史消息经 gzip + 隧道压缩,传输量最高省 90%,加载明显更快',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '断线重连升级指数退避(2 秒起翻倍、30 秒封顶、带抖动),网络闪断后恢复更稳更省电',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '服务器侧加固:全站强制 HTTPS、安全响应头、接口限流(本版起生效)',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.8.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '消息时间分隔条:间隔超过 5 分钟自动显示时间(QQ 同款)',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '回到底部悬浮按钮:翻看历史时新消息不再抢滚动,按钮带新消息小圆点',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '长按自己的气泡弹出"复制";AI 回复下方新增一键复制按钮',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '新消息入场动画(淡入上移)、下拉加载更早消息、聊天滚动条、更多触感反馈',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.8.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '四套主题:暗夜蓝 / 纯净白 / 护眼绿 / 樱花粉 — 抽屉"主题"里实时预览、一键切换、自动保存',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '界面产品级打磨:顶栏显示当前模型和生成状态,欢迎页带快捷建议(点一下直接开聊),气泡/输入栏/卡片的圆角阴影体系统一',
      ),
      ChangelogChange(ChangelogChangeType.improvement, '登录页、社区页、弹窗、菜单全部跟随主题换肤'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.4',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '快捷命令即时反馈:发送后立刻显示命令气泡和"正在执行"进度条,完成后原地更新为结果,压缩等长任务不再"消失"',
      ),
      ChangelogChange(
        ChangelogChangeType.feature,
        '网页端执行的命令也会实时显示在 App 对话里(进度和结果同步)',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '命令冲突等错误(如"当前正在进行压缩任务")持久显示在对话中,不再一闪而过',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.7.3',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复快捷命令不生效:改为走服务器命令通道(commands/execute)执行,与网页版点选一致;命令目录实时从服务器拉取',
      ),
      ChangelogChange(ChangelogChangeType.feature, '输入框直接输入 / 开头的消息也会按命令执行'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.2',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '输入框新增 + 快捷命令面板:/compact、/plan 一键执行,/goal、/feedback 快捷输入',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '命令执行结果直接显示在对话里,命令气泡不再卡在发送中状态',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.7.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '产品更名为 xHarness(应用名称与界面同步更新),产品官网同步上线',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.7.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '好友申请-确认流程:输好友码改为发送申请,对方接受后才成为好友;好友页可处理申请(接受/拒绝),新申请有系统通知',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '对方已向你发过申请时,你再发申请会自动互相通过',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.6.5',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复部分机型(小米/红米 Impeller 渲染)头像裁剪页全黑且无法操作:渲染路径改为直接绘制,不再使用 Transform 组件',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.6.4',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复头像裁剪页卡死:初始布局落在路由/键盘动画的瞬态小尺寸上导致图片缩到角落且手势失效,现改为视口变化自动重适配',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.6.3',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '全新应用图标(Hermes),Android 与 iOS 同步更新,应用内 Logo 同步替换',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.6.2',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '头像裁剪页显示当前缩放比例,新增一键复位按钮',
      ),
      ChangelogChange(ChangelogChangeType.fix, '裁剪页初始缩放与拖动的自动化测试覆盖'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复头像裁剪导出区域与预览不一致:改为完全自控的手势变换,导出与渲染严格同一映射',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.6.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '系统通知:好友私聊新消息自动弹通知(每分钟检查,按好友去重),审批请求与助手提问也会发通知',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.5.3',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '头像裁剪:选图后可拖动、双指缩放选择显示区域,确认后导出上传',
      ),
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复版本比较失真:分包 APK 的 versionCode 带架构偏移,发布脚本改为从 APK 读取真实值',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.5.2',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复定时检查更新永远不生效:30 分钟周期任务被一次性开关拦截,App 常驻后台时永远检测不到新版本',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '手动检查更新显示具体失败原因和本机/服务器版本号',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.5.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.fix,
        '修复头像上传失败(JSON 字段错误):服务端请求体上限从 64KB 提到 768KB,App 侧加强压缩',
      ),
      ChangelogChange(ChangelogChangeType.feature, '左侧边栏顶部显示社区头像与昵称,点击直达社区'),
    ],
  ),
  ChangelogRelease(
    version: '1.5.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '自定义头像:好友页点头像从相册选图(自动压缩),动态/排行榜/会话列表同步显示,可随时恢复字母头像',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.4.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '每 30 分钟自动静默检查更新,有新版时抽屉"检查更新"旁显示绿点',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '同一版本每次运行只自动弹一次更新提示,点"稍后"后不再打扰',
      ),
      ChangelogChange(
        ChangelogChangeType.improvement,
        '更新包改为 arm64 单架构,下载体积从 55MB 降到 19MB',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.4.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(ChangelogChangeType.feature, '社区功能:发布动态、点赞、一键分享自己的等级卡片'),
      ChangelogChange(
        ChangelogChangeType.feature,
        '好友功能:8 位好友码互相添加、好友等级排行榜、私聊(未读角标)',
      ),
      ChangelogChange(ChangelogChangeType.feature, '个人昵称设置与修改,首次进入社区自动分配好友码'),
    ],
  ),
  ChangelogRelease(
    version: '1.3.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.improvement,
        '升级流程优化:自动检测"安装未知应用"权限并引导开启,授权返回后自动继续下载',
      ),
    ],
  ),
  ChangelogRelease(
    version: '1.3.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '应用内检查更新:发现新版本后可直接下载并覆盖安装,无需数据线',
      ),
      ChangelogChange(ChangelogChangeType.feature, '抽屉新增"检查更新"手动入口'),
    ],
  ),
  ChangelogRelease(
    version: '1.2.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '新建会话可选择工作区目录:默认工作区一键创建,或从已注册工作区/自定义路径选择',
      ),
      ChangelogChange(ChangelogChangeType.feature, '对话中新建会话自动继承当前会话的工作区'),
      ChangelogChange(ChangelogChangeType.feature, '新增更新日志页面,版本更新后自动展示新功能'),
      ChangelogChange(ChangelogChangeType.improvement, '工作区分组支持折叠,折叠状态跨启动保留'),
    ],
  ),
  ChangelogRelease(
    version: '1.1.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(ChangelogChangeType.feature, '会话按工作区(目录)分组显示,支持折叠'),
      ChangelogChange(ChangelogChangeType.feature, '等级系统:按对话次数升级,抽屉中显示等级徽章与进度'),
      ChangelogChange(ChangelogChangeType.feature, '聊天记录与会话列表保存到本机存储,冷启动秒开'),
      ChangelogChange(ChangelogChangeType.feature, '模型选择支持推理强度,切换成功/失败均有提示'),
      ChangelogChange(ChangelogChangeType.improvement, '全新深色主题与聊天气泡设计'),
      ChangelogChange(ChangelogChangeType.improvement, '历史记录分页加载提速约 6 倍'),
      ChangelogChange(ChangelogChangeType.fix, '修复慢速网络下加载历史时丢失流式消息的问题'),
      ChangelogChange(ChangelogChangeType.fix, '修复快速切换会话时历史不刷新的问题'),
    ],
  ),
  ChangelogRelease(
    version: '1.0.0',
    date: '2026-08-19',
    changes: [
      ChangelogChange(
        ChangelogChangeType.feature,
        '首个版本:会话列表、流式对话、Markdown 渲染',
      ),
      ChangelogChange(ChangelogChangeType.feature, '工具调用卡片、审批与提问弹窗'),
      ChangelogChange(
        ChangelogChangeType.feature,
        '运行统计(轮次/耗时/token/缓存命中/上下文占用)',
      ),
      ChangelogChange(ChangelogChangeType.feature, '模型目录与切换'),
    ],
  ),
];

/// The latest release, for the post-update "what's new" dialog.
ChangelogRelease get kLatestRelease => kChangelog.first;

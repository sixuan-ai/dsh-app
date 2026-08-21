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
const kAppVersion = '1.10.10';

/// Release notes, newest first.
const kChangelog = [
  ChangelogRelease(
    version: '1.10.10',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '宠物视觉升级:使用原创 Q 版矢量精灵立绘替换 emoji,五大家族各有配色与特征,高阶形态增加光环/翅膀/角/尾巴和闪光特效,蛋快孵化时显示裂纹'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.9',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '训练家匹配赛:人机匹配对战(宝可梦风昵称/段位/胜率),新增段位系统 青铜🥉→王者👑,胜负影响段位分(胜+25/败-15)'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.8',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '宠物对战:挑战野生宠物,回合制战报+血条动画,五物种循环克制;胜者从主人处赢取 0.2M tokens 成长值(输了会被扣,历史对话 tokens 不受影响)'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.7',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '宠物家族更名宝可梦/洛克王国风格:哈灵/雷光猫/苍月狼/焚天炎龙/九天凤凰,每个形态都有专属名字(闪电喵→疾电猫→雷纹虎→雷霆狮皇…)'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.6',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '神秘蛋领养:随机抽取物种(灵宠/灵猫/神犬/神龙/凤凰五条进化链),孵化瞬间揭晓物种,名片显示物种标签'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.5',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '宠物进化:等级提升自动进化形态 🥚蛋蛋→🐥幼崽→🐱小猫→🐯猛虎→🐉神兽,进化时有庆祝弹窗;蛋快孵化时会提前破壳'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.4',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '启用正式发行签名(替换 debug 密钥),为后续上架应用商店做准备。注意:签名更换后旧版无法覆盖安装,需先卸载再装'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.3',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.fix,
          '修复提问/审批弹窗在网页端回答后不自动消失:现在另一端处理完会实时联动关闭,不用再重启 App'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.2',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '侧边栏瘦身:主题/宠物/权限模式/更新/日志/退出收进「更多功能」九宫格,会话列表拿回全部高度;更新提示红点透传到入口上'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.1',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '宠物成长改为按对话 tokens 计算:每命中 1M tokens 升一级,喂食/玩耍/洗澡只管饱腹/心情/清洁'),
      ChangelogChange(ChangelogChangeType.fix,
          '修复浅色主题下发送按钮隐形(点原位置仍可发出):HyperOS 上 Ink+渐变不绘制,已换成 Container 实现'),
    ],
  ),
  ChangelogRelease(
    version: '1.10.0',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '新增宠物功能:领养一只专属小可爱,喂食/玩耍/洗澡照顾它,状态会随时间变化,还有成长等级(抽屉 → 宠物)'),
      ChangelogChange(ChangelogChangeType.feature,
          '抽屉新增「权限模式」入口:一键切换工作区写入/完全访问,完全访问带风险确认,不用再手敲 /permission 命令'),
      ChangelogChange(ChangelogChangeType.fix,
          '修复审批/提问弹窗可被返回键误关:关闭后不再消失,未回答时自动重新弹出,不再卡住对话'),
      ChangelogChange(ChangelogChangeType.fix,
          '修复快捷命令面板显示不全:命令较多时(如 /permission)可上下滑动完整浏览'),
    ],
  ),
  ChangelogRelease(
    version: '1.9.2',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.fix,
          '回答提问/审批时若已失效(如 dsh 服务重启),现在会明确提示"回答未送达",不再静默吞掉'),
    ],
  ),
  ChangelogRelease(
    version: '1.9.1',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '升级弹窗全新设计:渐变头部+更新日志卡片+全宽渐变按钮;下载进度改为大圆环+实时网速,失败可一键重试'),
    ],
  ),
  ChangelogRelease(
    version: '1.9.0',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '多实例登录:登录时按用户名自动连接到你的 dsh 实例(本机/Mac),无需关心域名'),
      ChangelogChange(ChangelogChangeType.improvement,
          '登录后记住所属实例,启动直连不再绕路;社交与更新仍走主域,不受实例切换影响'),
    ],
  ),
  ChangelogRelease(
    version: '1.8.2',
    date: '2026-08-21',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '链路提速:历史消息经 gzip + 隧道压缩,传输量最高省 90%,加载明显更快'),
      ChangelogChange(ChangelogChangeType.improvement,
          '断线重连升级指数退避(2 秒起翻倍、30 秒封顶、带抖动),网络闪断后恢复更稳更省电'),
      ChangelogChange(ChangelogChangeType.improvement,
          '服务器侧加固:全站强制 HTTPS、安全响应头、接口限流(本版起生效)'),
    ],
  ),
  ChangelogRelease(
    version: '1.8.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '消息时间分隔条:间隔超过 5 分钟自动显示时间(QQ 同款)'),
      ChangelogChange(ChangelogChangeType.feature,
          '回到底部悬浮按钮:翻看历史时新消息不再抢滚动,按钮带新消息小圆点'),
      ChangelogChange(ChangelogChangeType.feature,
          '长按自己的气泡弹出"复制";AI 回复下方新增一键复制按钮'),
      ChangelogChange(ChangelogChangeType.improvement,
          '新消息入场动画(淡入上移)、下拉加载更早消息、聊天滚动条、更多触感反馈'),
    ],
  ),
  ChangelogRelease(
    version: '1.8.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(ChangelogChangeType.feature,
          '四套主题:暗夜蓝 / 纯净白 / 护眼绿 / 樱花粉 — 抽屉"主题"里实时预览、一键切换、自动保存'),
      ChangelogChange(ChangelogChangeType.improvement,
          '界面产品级打磨:顶栏显示当前模型和生成状态,欢迎页带快捷建议(点一下直接开聊),气泡/输入栏/卡片的圆角阴影体系统一'),
      ChangelogChange(ChangelogChangeType.improvement,
          '登录页、社区页、弹窗、菜单全部跟随主题换肤'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.4',
    date: '2026-08-20',
    changes: [
      ChangelogChange(ChangelogChangeType.improvement,
          '快捷命令即时反馈:发送后立刻显示命令气泡和"正在执行"进度条,完成后原地更新为结果,压缩等长任务不再"消失"'),
      ChangelogChange(ChangelogChangeType.feature,
          '网页端执行的命令也会实时显示在 App 对话里(进度和结果同步)'),
      ChangelogChange(ChangelogChangeType.improvement,
          '命令冲突等错误(如"当前正在进行压缩任务")持久显示在对话中,不再一闪而过'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.3',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.fix, '修复快捷命令不生效:改为走服务器命令通道(commands/execute)执行,与网页版点选一致;命令目录实时从服务器拉取'),
      ChangelogChange(
          ChangelogChangeType.feature, '输入框直接输入 / 开头的消息也会按命令执行'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.2',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '输入框新增 + 快捷命令面板:/compact、/plan 一键执行,/goal、/feedback 快捷输入'),
      ChangelogChange(
          ChangelogChangeType.improvement, '命令执行结果直接显示在对话里,命令气泡不再卡在发送中状态'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.improvement, '产品更名为 xHarmess(应用名称与界面同步更新),产品官网同步上线'),
    ],
  ),
  ChangelogRelease(
    version: '1.7.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '好友申请-确认流程:输好友码改为发送申请,对方接受后才成为好友;好友页可处理申请(接受/拒绝),新申请有系统通知'),
      ChangelogChange(
          ChangelogChangeType.improvement, '对方已向你发过申请时,你再发申请会自动互相通过'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.5',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.fix, '修复部分机型(小米/红米 Impeller 渲染)头像裁剪页全黑且无法操作:渲染路径改为直接绘制,不再使用 Transform 组件'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.4',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.fix, '修复头像裁剪页卡死:初始布局落在路由/键盘动画的瞬态小尺寸上导致图片缩到角落且手势失效,现改为视口变化自动重适配'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.3',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.improvement, '全新应用图标(Hermes),Android 与 iOS 同步更新,应用内 Logo 同步替换'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.2',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.improvement, '头像裁剪页显示当前缩放比例,新增一键复位按钮'),
      ChangelogChange(
          ChangelogChangeType.fix, '裁剪页初始缩放与拖动的自动化测试覆盖'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.fix, '修复头像裁剪导出区域与预览不一致:改为完全自控的手势变换,导出与渲染严格同一映射'),
    ],
  ),
  ChangelogRelease(
    version: '1.6.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '系统通知:好友私聊新消息自动弹通知(每分钟检查,按好友去重),审批请求与助手提问也会发通知'),
    ],
  ),
  ChangelogRelease(
    version: '1.5.3',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '头像裁剪:选图后可拖动、双指缩放选择显示区域,确认后导出上传'),
      ChangelogChange(
          ChangelogChangeType.fix, '修复版本比较失真:分包 APK 的 versionCode 带架构偏移,发布脚本改为从 APK 读取真实值'),
    ],
  ),
  ChangelogRelease(
    version: '1.5.2',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.fix, '修复定时检查更新永远不生效:30 分钟周期任务被一次性开关拦截,App 常驻后台时永远检测不到新版本'),
      ChangelogChange(
          ChangelogChangeType.improvement, '手动检查更新显示具体失败原因和本机/服务器版本号'),
    ],
  ),
  ChangelogRelease(
    version: '1.5.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.fix, '修复头像上传失败(JSON 字段错误):服务端请求体上限从 64KB 提到 768KB,App 侧加强压缩'),
      ChangelogChange(
          ChangelogChangeType.feature, '左侧边栏顶部显示社区头像与昵称,点击直达社区'),
    ],
  ),
  ChangelogRelease(
    version: '1.5.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '自定义头像:好友页点头像从相册选图(自动压缩),动态/排行榜/会话列表同步显示,可随时恢复字母头像'),
    ],
  ),
  ChangelogRelease(
    version: '1.4.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '每 30 分钟自动静默检查更新,有新版时抽屉"检查更新"旁显示绿点'),
      ChangelogChange(
          ChangelogChangeType.improvement, '同一版本每次运行只自动弹一次更新提示,点"稍后"后不再打扰'),
      ChangelogChange(
          ChangelogChangeType.improvement, '更新包改为 arm64 单架构,下载体积从 55MB 降到 19MB'),
    ],
  ),
  ChangelogRelease(
    version: '1.4.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '社区功能:发布动态、点赞、一键分享自己的等级卡片'),
      ChangelogChange(
          ChangelogChangeType.feature, '好友功能:8 位好友码互相添加、好友等级排行榜、私聊(未读角标)'),
      ChangelogChange(
          ChangelogChangeType.feature, '个人昵称设置与修改,首次进入社区自动分配好友码'),
    ],
  ),
  ChangelogRelease(
    version: '1.3.1',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.improvement, '升级流程优化:自动检测"安装未知应用"权限并引导开启,授权返回后自动继续下载'),
    ],
  ),
  ChangelogRelease(
    version: '1.3.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '应用内检查更新:发现新版本后可直接下载并覆盖安装,无需数据线'),
      ChangelogChange(
          ChangelogChangeType.feature, '抽屉新增"检查更新"手动入口'),
    ],
  ),
  ChangelogRelease(
    version: '1.2.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '新建会话可选择工作区目录:默认工作区一键创建,或从已注册工作区/自定义路径选择'),
      ChangelogChange(
          ChangelogChangeType.feature, '对话中新建会话自动继承当前会话的工作区'),
      ChangelogChange(
          ChangelogChangeType.feature, '新增更新日志页面,版本更新后自动展示新功能'),
      ChangelogChange(
          ChangelogChangeType.improvement, '工作区分组支持折叠,折叠状态跨启动保留'),
    ],
  ),
  ChangelogRelease(
    version: '1.1.0',
    date: '2026-08-20',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '会话按工作区(目录)分组显示,支持折叠'),
      ChangelogChange(
          ChangelogChangeType.feature, '等级系统:按对话次数升级,抽屉中显示等级徽章与进度'),
      ChangelogChange(
          ChangelogChangeType.feature, '聊天记录与会话列表保存到本机存储,冷启动秒开'),
      ChangelogChange(
          ChangelogChangeType.feature, '模型选择支持推理强度,切换成功/失败均有提示'),
      ChangelogChange(ChangelogChangeType.improvement, '全新深色主题与聊天气泡设计'),
      ChangelogChange(ChangelogChangeType.improvement, '历史记录分页加载提速约 6 倍'),
      ChangelogChange(
          ChangelogChangeType.fix, '修复慢速网络下加载历史时丢失流式消息的问题'),
      ChangelogChange(
          ChangelogChangeType.fix, '修复快速切换会话时历史不刷新的问题'),
    ],
  ),
  ChangelogRelease(
    version: '1.0.0',
    date: '2026-08-19',
    changes: [
      ChangelogChange(
          ChangelogChangeType.feature, '首个版本:会话列表、流式对话、Markdown 渲染'),
      ChangelogChange(
          ChangelogChangeType.feature, '工具调用卡片、审批与提问弹窗'),
      ChangelogChange(
          ChangelogChangeType.feature, '运行统计(轮次/耗时/token/缓存命中/上下文占用)'),
      ChangelogChange(ChangelogChangeType.feature, '模型目录与切换'),
    ],
  ),
];

/// The latest release, for the post-update "what's new" dialog.
ChangelogRelease get kLatestRelease => kChangelog.first;

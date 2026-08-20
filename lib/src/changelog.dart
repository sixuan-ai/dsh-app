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
const kAppVersion = '1.7.4';

/// Release notes, newest first.
const kChangelog = [
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

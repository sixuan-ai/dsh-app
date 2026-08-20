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
const kAppVersion = '1.3.0';

/// Release notes, newest first.
const kChangelog = [
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

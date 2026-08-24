/// Lightweight app localization: a const strings table per language plus a
/// controller that persists the selection and rebuilds the app root.
///
/// Follows the same pattern as the theme system: the app root listens to
/// [LanguageController] and reassigns the global [S] accessor in [build], so
/// every widget reads the active language without threading it through.
/// 'system' follows the OS locale; zh/en are explicit overrides.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One language option shown in the settings picker.
class LanguageOption {
  const LanguageOption(this.id, this.locale);
  final String id;

  /// MaterialApp locale; null means "follow the system".
  final Locale? locale;
}

/// Picker order; labels render in their own language (standard practice).
const kLanguages = [
  LanguageOption('system', null),
  LanguageOption('zh', Locale('zh')),
  LanguageOption('en', Locale('en')),
];

/// The active strings table; reassigned by the app root on language change.
Strings S = Strings.zh;

/// Selected-language store: persists the id and notifies the app root.
class LanguageController extends ChangeNotifier {
  String _languageId = 'system';

  /// The persisted selection (a [kLanguages] id).
  String get languageId => _languageId;

  /// The strings table of the current selection (system → zh).
  Strings get s => _languageId == 'en' ? Strings.en : Strings.zh;

  /// The resolved MaterialApp locale (null follows the system).
  Locale? get locale {
    for (final option in kLanguages) {
      if (option.id == _languageId) return option.locale;
    }
    return null;
  }

  /// Loads the persisted selection; call once at app start.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('languageId');
    if (stored != null && stored != _languageId) {
      _languageId = stored;
      notifyListeners();
    }
  }

  /// Selects and persists a language (no-op for unknown ids).
  Future<void> select(String id) async {
    if (id == _languageId || kLanguages.every((o) => o.id != id)) return;
    _languageId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageId', id);
  }
}

/// All user-facing strings that ship in both languages. Only the core
/// surfaces are localized for now (settings, drawer, connection center,
/// feedback/support, update dialogs, login); long-form pages stay zh and
/// migrate progressively.
class Strings {
  const Strings({
    required this.settings,
    required this.language,
    required this.followSystem,
    required this.simplifiedChinese,
    required this.theme,
    required this.connection,
    required this.connectionCenter,
    required this.feedback,
    required this.support,
    required this.help,
    required this.updateLog,
    required this.checkUpdate,
    required this.connectionGuide,
    required this.about,
    required this.version,
    required this.cancel,
    required this.confirm,
    required this.save,
    required this.submit,
    required this.loading,
    required this.retry,
    required this.moreFeatures,
    required this.connectionSafety,
    required this.localRemote,
    required this.connectionTutorial,
    required this.computerConfig,
    required this.aiDaily,
    required this.aiLearning,
    required this.realtimeFeed,
    required this.agentTutorial,
    required this.pet,
    required this.directoryBrowse,
    required this.computerDirectories,
    required this.networkDiagnosis,
    required this.latencyJitter,
    required this.permissionMode,
    required this.logout,
    required this.hkServer,
    required this.szServer,
    required this.localComputer,
    required this.currentlyUsing,
    required this.switchBackToHk,
    required this.switchToSz,
    required this.switchToLocal,
    required this.currentConnection,
    required this.connected,
    required this.switchedToLocal,
    required this.switchedToSz,
    required this.switchedToRemote,
    required this.switchFailedKeep,
    required this.switchFailed,
    required this.noConnectionTarget,
    required this.retestLocal,
    required this.hkServerDesc,
    required this.szServerDesc,
    required this.localDescAvailable,
    required this.localDescNone,
    required this.checkingLocal,
    required this.switchTip,
    required this.feedbackTitle,
    required this.feedbackType,
    required this.typeBug,
    required this.typeSuggestion,
    required this.typeOther,
    required this.describe,
    required this.describeHint,
    required this.contact,
    required this.contactHint,
    required this.feedbackDesc,
    required this.communityDesc,
    required this.submitSuccess,
    required this.submitFailed,
    required this.supportTitle,
    required this.supportIntro,
    required this.community,
    required this.newSession,
    required this.workspace,
    required this.running,
    required this.archived,
    required this.pinned,
    required this.enableFullAccess,
    required this.fullAccessWarning,
    required this.enable,
    required this.fullAccess,
    required this.pickTheme,
    required this.appliesInstantly,
    required this.modeGoal,
    required this.modePlan,
    required this.modeAuto,
    required this.sessionName,
    required this.tagline,
    required this.remoteConnection,
    required this.localConnection,
    required this.lanHomeDesc,
    required this.remoteOutDesc,
    required this.howToConfig,
    required this.lanSecurityWarning,
    required this.lanUrlHint,
    required this.username,
    required this.password,
    required this.showPassword,
    required this.hidePassword,
    required this.updateAvailableTitle,
    required this.download,
    required this.updateNow,
    required this.later,
    required this.downloadingUpdate,
    required this.installPackage,
    required this.newVersion,
    required this.balanceTitle,
    required this.balanceServerNote,
    required this.balanceQuery,
    required this.balanceServerNoKey,
    required this.balanceAvailable,
    required this.balanceUnavailable,
    required this.balanceTotal,
    required this.balanceGranted,
    required this.balanceToppedUp,
    required this.balanceRefresh,
    required this.balanceQueryFailed,
  });

  final String settings;
  final String language;
  final String followSystem;
  final String simplifiedChinese;
  final String theme;
  final String connection;
  final String connectionCenter;
  final String feedback;
  final String support;
  final String help;
  final String updateLog;
  final String checkUpdate;
  final String connectionGuide;
  final String about;
  final String version;
  final String cancel;
  final String confirm;
  final String save;
  final String submit;
  final String loading;
  final String retry;
  final String moreFeatures;
  final String connectionSafety;
  final String localRemote;
  final String connectionTutorial;
  final String computerConfig;
  final String aiDaily;
  final String aiLearning;
  final String realtimeFeed;
  final String agentTutorial;
  final String pet;
  final String directoryBrowse;
  final String computerDirectories;
  final String networkDiagnosis;
  final String latencyJitter;
  final String permissionMode;
  final String logout;
  final String hkServer;
  final String szServer;
  final String localComputer;
  final String currentlyUsing;
  final String switchBackToHk;
  final String switchToSz;
  final String switchToLocal;
  final String currentConnection;
  final String connected;
  final String switchedToLocal;
  final String switchedToSz;
  final String switchedToRemote;
  final String switchFailedKeep;
  final String switchFailed;
  final String noConnectionTarget;
  final String retestLocal;
  final String hkServerDesc;
  final String szServerDesc;
  final String localDescAvailable;
  final String localDescNone;
  final String checkingLocal;
  final String switchTip;
  final String feedbackTitle;
  final String feedbackType;
  final String typeBug;
  final String typeSuggestion;
  final String typeOther;
  final String describe;
  final String describeHint;
  final String contact;
  final String contactHint;
  final String feedbackDesc;
  final String communityDesc;
  final String submitSuccess;
  final String submitFailed;
  final String supportTitle;
  final String supportIntro;
  final String community;
  final String newSession;
  final String workspace;
  final String running;
  final String archived;
  final String pinned;
  final String enableFullAccess;
  final String fullAccessWarning;
  final String enable;
  final String fullAccess;
  final String pickTheme;
  final String appliesInstantly;
  final String modeGoal;
  final String modePlan;
  final String modeAuto;
  final String sessionName;
  final String tagline;
  final String remoteConnection;
  final String localConnection;
  final String lanHomeDesc;
  final String remoteOutDesc;
  final String howToConfig;
  final String lanSecurityWarning;
  final String lanUrlHint;
  final String username;
  final String password;
  final String showPassword;
  final String hidePassword;
  final String updateAvailableTitle;
  final String download;
  final String updateNow;
  final String later;
  final String downloadingUpdate;
  final String installPackage;
  final String newVersion;
  final String balanceTitle;
  final String balanceServerNote;
  final String balanceQuery;
  final String balanceServerNoKey;
  final String balanceAvailable;
  final String balanceUnavailable;
  final String balanceTotal;
  final String balanceGranted;
  final String balanceToppedUp;
  final String balanceRefresh;
  final String balanceQueryFailed;

  static const zh = Strings(
    settings: '设置',
    language: '语言',
    followSystem: '跟随系统',
    simplifiedChinese: '简体中文',
    theme: '主题',
    connection: '连接',
    connectionCenter: '连接中心',
    feedback: '用户反馈',
    support: '联系客服',
    help: '帮助',
    updateLog: '更新日志',
    checkUpdate: '检查更新',
    connectionGuide: '连接教程',
    about: '关于',
    version: '版本',
    cancel: '取消',
    confirm: '确定',
    save: '保存',
    submit: '提交',
    loading: '加载中…',
    retry: '重试',
    moreFeatures: '更多功能',
    connectionSafety: '连接与安全',
    localRemote: '本地 / 远程',
    connectionTutorial: '连接教程',
    computerConfig: '电脑配置',
    aiDaily: 'AI 日报',
    aiLearning: 'AI 知识学习',
    realtimeFeed: '实时聚合',
    agentTutorial: 'Agent 教程',
    pet: '宠物',
    directoryBrowse: '目录浏览',
    computerDirectories: '电脑上的目录',
    networkDiagnosis: '网络诊断',
    latencyJitter: '延迟与抖动',
    permissionMode: '权限模式',
    logout: '退出登录',
    hkServer: '香港服务器',
    szServer: '深圳服务器',
    localComputer: '本地电脑',
    currentlyUsing: '当前正在使用',
    switchBackToHk: '切换回香港服务器',
    switchToSz: '切换到深圳服务器',
    switchToLocal: '切换到本地电脑',
    currentConnection: '当前连接',
    connected: '已连接',
    switchedToLocal: '已切换到本地连接',
    switchedToSz: '已切换到深圳直连',
    switchedToRemote: '已切换到远程连接',
    switchFailedKeep: '切换失败，已保持原来的连接',
    switchFailed: '切换失败: ',
    noConnectionTarget: '没有可用的连接地址，请先完成连接配置',
    retestLocal: '重新检测本地连接',
    hkServerDesc: '通过香港服务器中转，适合外出使用',
    szServerDesc: '国内直连，延迟更低更稳',
    localDescAvailable: '本地电脑可用，通常速度更快',
    localDescNone: '当前未检测到本地电脑',
    checkingLocal: '正在检查电脑…',
    switchTip: '切换连接不会退出账号。正在生成内容时建议等待完成后再切换。',
    feedbackTitle: '用户反馈',
    feedbackType: '反馈类型',
    typeBug: '功能问题',
    typeSuggestion: '体验建议',
    typeOther: '其他',
    describe: '问题描述',
    describeHint: '请详细描述你遇到的问题或建议…',
    contact: '联系方式（选填）',
    contactHint: '微信号 / QQ / 邮箱，便于我们回复你',
    feedbackDesc: '问题、建议，告诉我们',
    communityDesc: '和其他用户交流',
    submitSuccess: '反馈已提交，感谢你的支持！',
    submitFailed: '提交失败，请稍后重试',
    supportTitle: '联系客服',
    supportIntro: '以下站内渠道可以帮你解决问题：',
    community: '社区',
    newSession: '新会话',
    workspace: '工作区',
    running: '运行中',
    archived: '已归档',
    pinned: '已置顶',
    enableFullAccess: '开启完全访问?',
    fullAccessWarning: '开启后 DSH 可读写设备上所有文件,且不再弹出审批确认。仅在信任当前任务时开启,可随时切回工作区写入。',
    enable: '开启',
    fullAccess: '完全访问',
    pickTheme: '选择主题',
    appliesInstantly: '立即生效,自动保存',
    modeGoal: '目标模式',
    modePlan: '计划模式',
    modeAuto: '自动模式',
    sessionName: '会话名称',
    tagline: '用手机安全连接并操作你自己的电脑',
    remoteConnection: '远程连接',
    localConnection: '本地连接',
    lanHomeDesc: '适合在家使用：手机和电脑同一 Wi-Fi，速度快，但离开家后不可用',
    remoteOutDesc: '适合外出使用：由官网找到你的电脑，安全要求更高，电脑需要保持在线',
    howToConfig: '怎么配置？',
    lanSecurityWarning: '当前本地连接适合可信家庭网络。不要在酒店、商场或公共 Wi-Fi 使用，也不要把电脑端口直接开放到互联网。',
    lanUrlHint: '电脑地址，例如 192.168.1.100:3080',
    username: '用户名',
    password: '密码',
    showPassword: '显示密码',
    hidePassword: '隐藏密码',
    updateAvailableTitle: '发现新版本',
    download: '下载',
    updateNow: '立即更新',
    later: '稍后',
    downloadingUpdate: '正在下载更新',
    installPackage: '安装包',
    newVersion: '新版本',
    balanceTitle: 'API 余额',
    balanceServerNote: '余额通过你电脑上的 DSH 直接查询，API 密钥不会传到手机',
    balanceQuery: '查询余额',
    balanceServerNoKey: '服务器未配置 DEEPSEEK_API_KEY',
    balanceAvailable: '可用',
    balanceUnavailable: '不可用',
    balanceTotal: '可用总额',
    balanceGranted: '赠金',
    balanceToppedUp: '充值',
    balanceRefresh: '刷新',
    balanceQueryFailed: '查询失败',
  );

  static const en = Strings(
    settings: 'Settings',
    language: 'Language',
    followSystem: 'Follow system',
    simplifiedChinese: '简体中文',
    theme: 'Theme',
    connection: 'Connection',
    connectionCenter: 'Connection Center',
    feedback: 'Feedback',
    support: 'Contact Support',
    help: 'Help',
    updateLog: 'Changelog',
    checkUpdate: 'Check for Updates',
    connectionGuide: 'Setup Guide',
    about: 'About',
    version: 'Version',
    cancel: 'Cancel',
    confirm: 'OK',
    save: 'Save',
    submit: 'Submit',
    loading: 'Loading…',
    retry: 'Retry',
    moreFeatures: 'More',
    connectionSafety: 'Connection & Security',
    localRemote: 'Local / Remote',
    connectionTutorial: 'Setup Guide',
    computerConfig: 'Computer Setup',
    aiDaily: 'AI Daily',
    aiLearning: 'AI Learning',
    realtimeFeed: 'Live feed',
    agentTutorial: 'Agent tutorial',
    pet: 'Pet',
    directoryBrowse: 'Files',
    computerDirectories: 'Computer folders',
    networkDiagnosis: 'Network Diag',
    latencyJitter: 'Latency & Jitter',
    permissionMode: 'Permission Mode',
    logout: 'Log Out',
    hkServer: 'HK server',
    szServer: 'SZ server',
    localComputer: 'Local PC',
    currentlyUsing: 'In use',
    switchBackToHk: 'Switch back to HK server',
    switchToSz: 'Switch to SZ server',
    switchToLocal: 'Switch to local PC',
    currentConnection: 'Current connection',
    connected: 'Connected',
    switchedToLocal: 'Switched to local connection',
    switchedToSz: 'Switched to Shenzhen direct',
    switchedToRemote: 'Switched to remote connection',
    switchFailedKeep: 'Switch failed, keeping the previous connection',
    switchFailed: 'Switch failed: ',
    noConnectionTarget:
        'No connection target available, please configure first',
    retestLocal: 'Re-check local connection',
    hkServerDesc: 'Relayed via Hong Kong, good for travel',
    szServerDesc: 'Direct domestic line, lower latency',
    localDescAvailable: 'Local PC available, usually fastest',
    localDescNone: 'No local PC detected',
    checkingLocal: 'Checking PC…',
    switchTip:
        'Switching keeps you signed in. Prefer to wait until generation finishes.',
    feedbackTitle: 'Feedback',
    feedbackType: 'Category',
    typeBug: 'Issue',
    typeSuggestion: 'Suggestion',
    typeOther: 'Other',
    describe: 'Description',
    describeHint: 'Describe the problem or suggestion…',
    contact: 'Contact (optional)',
    contactHint: 'WeChat / QQ / email so we can reply',
    feedbackDesc: 'Tell us about issues or ideas',
    communityDesc: 'Chat with other users',
    submitSuccess: 'Feedback submitted. Thank you!',
    submitFailed: 'Submit failed, please try again later',
    supportTitle: 'Contact Support',
    supportIntro: 'In-app channels that can help you:',
    community: 'Community',
    newSession: 'New Session',
    workspace: 'Workspace',
    running: 'Running',
    archived: 'Archived',
    pinned: 'Pinned',
    enableFullAccess: 'Enable full access?',
    fullAccessWarning:
        'DSH can then read/write all files on this device without approvals. Enable only when you trust the task; you can switch back anytime.',
    enable: 'Enable',
    fullAccess: 'Full access',
    pickTheme: 'Pick a theme',
    appliesInstantly: 'Applies instantly and saves',
    modeGoal: 'Goal mode',
    modePlan: 'Plan mode',
    modeAuto: 'Auto mode',
    sessionName: 'Session name',
    tagline: 'Securely connect to and control your own PC from your phone',
    remoteConnection: 'Remote',
    localConnection: 'Local',
    lanHomeDesc:
        'Best at home: phone and PC on the same Wi-Fi, fast, but unavailable away from home',
    remoteOutDesc:
        'Best on the go: reach your PC via the website, stricter security, PC must stay online',
    howToConfig: 'How to set up?',
    lanSecurityWarning:
        'Local mode is for trusted home networks. Do not use it on public Wi-Fi or expose PC ports to the internet.',
    lanUrlHint: 'PC address, e.g. 192.168.1.100:3080',
    username: 'Username',
    password: 'Password',
    showPassword: 'Show password',
    hidePassword: 'Hide password',
    updateAvailableTitle: 'Update available',
    download: 'Download',
    updateNow: 'Update now',
    later: 'Later',
    downloadingUpdate: 'Downloading update',
    installPackage: 'Package',
    newVersion: 'New version',
    balanceTitle: 'API Balance',
    balanceQuery: 'Check Balance',
    balanceServerNote:
        "Balance is queried via your PC's DSH; the API key never leaves the host",
    balanceServerNoKey: 'DEEPSEEK_API_KEY is not configured on the server',
    balanceAvailable: 'Available',
    balanceUnavailable: 'Unavailable',
    balanceTotal: 'Total balance',
    balanceGranted: 'Granted',
    balanceToppedUp: 'Topped up',
    balanceRefresh: 'Refresh',
    balanceQueryFailed: 'Query failed',
  );
}

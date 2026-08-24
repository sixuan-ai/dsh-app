/// xHarness — Flutter client for the DeepSeek Harness web API.
///
/// Server URL is a built-in default; the user only ever enters credentials.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/changelog.dart';
import 'login_view.dart';
import 'connection_guide.dart';
import 'brand_mark.dart';
import 'src/notifications.dart';
import 'src/protocol.dart';
import 'src/social.dart';
import 'update_dialogs.dart';
import 'src/theme.dart';
import 'src/updater.dart';
import 'chat_view.dart';
import 'session_drawer.dart';
import 'session_header.dart';
import 'stats_bar.dart';
import 'model_picker.dart';
import 'changelog_view.dart';
import 'new_session_sheet.dart';
import 'composer.dart';
import 'state.dart';

/// Built-in server endpoint (frp tunnel → auth proxy → dsh web).
const kDefaultServerUrl = 'https://dsh.ainotex.com';

/// Release manifest polled by the in-app updater. During development this can
/// point at a LAN server (e.g. http://192.168.1.5:8000/latest.json) for fast
/// download tests; production uses the public domain.
const kUpdateManifestUrl = 'https://dsh.ainotex.com/releases/latest.json';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(NotificationService.instance.init());
  runApp(const DshApp());
}

class DshApp extends StatefulWidget {
  const DshApp({super.key});

  @override
  State<DshApp> createState() => _DshAppState();
}

class _DshAppState extends State<DshApp> {
  final AppState appState = AppState();
  final ThemeController theme = ThemeController();
  bool _restored = false;
  bool _hasCreds = false;

  @override
  void initState() {
    super.initState();
    theme.addListener(_onThemeChanged);
    unawaited(theme.load());
    _restore();
  }

  void _onThemeChanged() => setState(() {});

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('authUser');
    final pass = prefs.getString('authPass');
    if (user != null && pass != null && user.isNotEmpty) {
      _hasCreds = true;
      // The instance URL was resolved through the directory at login;
      // reconnect to it directly (no directory round-trip at boot).
      final mode = prefs.getString('connectionMode') ?? 'public';
      final serverUrl = mode == 'lan'
          ? (prefs.getString('lanServerUrl') ??
                prefs.getString('serverUrl') ??
                kDefaultServerUrl)
          : (prefs.getString('serverUrl') ?? kDefaultServerUrl);
      unawaited(appState.connect(serverUrl, username: user, password: pass));
    }
    if (mounted) setState(() => _restored = true);
  }

  @override
  void dispose() {
    theme.removeListener(_onThemeChanged);
    theme.dispose();
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Publish the active palette before the tree reads it; a theme change
    // rebuilds from this root, so every P read observes the new palette.
    P = theme.palette;
    return MaterialApp(
      title: 'xHarness',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(P),
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          if (!_restored) return const _Splash(label: '正在启动…');
          if (appState.connected) {
            return HomePage(state: appState, theme: theme);
          }
          if (_hasCreds && appState.connecting) {
            return const _Splash(label: '正在连接服务器…');
          }
          return ServerSetupPage(
            state: appState,
            defaultServerUrl: kDefaultServerUrl,
          );
        },
      ),
    );
  }
}

/// Branded boot/connection splash.
class _Splash extends StatelessWidget {
  const _Splash({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 76),
            const SizedBox(height: 20),
            Text(label, style: TextStyle(color: P.textSecondary)),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient app logo tile.
class QuickStartSheet extends StatelessWidget {
  const QuickStartSheet({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.add_comment_outlined, '新建会话', '点击右上角或侧边栏“新建会话”，选择电脑上的工作目录。'),
      (Icons.chat_bubble_outline, '发送任务', '像聊天一样描述需求；可以发送文字和图片，也可以用 / 打开快捷命令。'),
      (Icons.approval_outlined, '处理确认', '涉及文件和命令时，App 会弹出审批或问题，请确认后任务才会继续。'),
      (Icons.menu, '管理与更多功能', '左上角菜单可切换会话、查看宠物、连接教程、权限模式和更新。'),
    ];
    return Material(
      color: P.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第一次使用？先看这四步',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '四步快速上手，之后可在“更多功能 → 连接教程”重新查看配置。',
                style: TextStyle(color: P.textSecondary),
              ),
              const SizedBox(height: 18),
              for (final (icon, title, detail) in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: P.accent.withValues(alpha: 0.12),
                    child: Icon(icon, color: P.accentLight),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(detail),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('开始使用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.theme});

  final AppState state;
  final ThemeController theme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Set<String> _shownApprovals = {};
  final Set<String> _shownQuestions = {};
  String? _modelsLoadedFor;

  /// Newer release known to the server; drives the green dot on the
  /// 检查更新 drawer entry. Set by the launch check and the periodic timer.
  UpdateInfo? _availableUpdate;

  /// versionCode already auto-prompted this run; 稍后 then stays quiet
  /// (the green dot remains) until the next launch.
  int _updateDialogShownFor = -1;
  bool _updateCheckInFlight = false;
  bool _updateDialogOpen = false;
  bool _updateFlowActive = false;
  Timer? _updateTimer;

  /// Social message poller state; watermarks persist per peer so a message
  /// notifies once across restarts.
  Timer? _socialTimer;
  bool _socialFirstPoll = true;

  /// Update deferred while the user grants install-unknown-apps in settings;
  /// resumed lifecycle restarts it automatically.
  ({UpdateChecker checker, UpdateInfo info})? _pendingUpdate;

  bool _checkingLocal = false;
  bool _localAvailable = false;
  String? _localUrl;
  String _connectionMode = 'public';
  String? _remoteUrl;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWhatsNew();
      _maybeShowQuickStart();
      _checkForUpdate();
    });
    // Silent re-check every 30 minutes; a find raises the green dot.
    _updateTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _checkForUpdate(),
    );
    // Private-message notifications: first poll primes watermarks silently.
    _socialTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pollSocial(),
    );
    Timer(const Duration(seconds: 8), _pollSocial);
    Timer(const Duration(seconds: 2), _checkLocalConnection);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _socialTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLocalConnection() async {
    if (_checkingLocal || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final localUrl = prefs.getString('lanServerUrl');
    final mode = prefs.getString('connectionMode') ?? 'public';
    final remoteUrl = prefs.getString('remoteServerUrl');
    if (localUrl == null || localUrl.isEmpty) {
      if (mounted) setState(() => _localAvailable = false);
      return;
    }
    setState(() {
      _checkingLocal = true;
      _localUrl = localUrl;
      _connectionMode = mode;
      _remoteUrl = remoteUrl;
    });
    final available = await state.probeServer(
      localUrl,
      username: state.authUsername,
      password: state.authPassword,
    );
    if (!mounted) return;
    setState(() {
      _checkingLocal = false;
      _localAvailable = available;
    });
  }

  Future<void> _switchConnection(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    var target = mode == 'lan' ? _localUrl : _remoteUrl;
    if (mode == 'public' && (target == null || target.isEmpty)) {
      final user = state.authUsername;
      final pass = state.authPassword;
      if (user != null && pass != null) {
        try {
          target = await directoryLogin(kDefaultServerUrl, user, pass);
          await prefs.setString('remoteServerUrl', target);
        } catch (_) {
          target = null;
        }
      }
    }
    if (target == null || target.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可用的连接地址，请先完成连接配置')));
      return;
    }
    final previousMode = _connectionMode;
    final ok = await state.switchConnection(target);
    if (!mounted) return;
    if (ok) {
      await prefs.setString('connectionMode', mode);
      await prefs.setString('serverUrl', target);
      if (!mounted) return;
      setState(() => _connectionMode = mode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mode == 'lan' ? '已切换到本地连接' : '已切换到远程连接')),
      );
    } else {
      setState(() => _connectionMode = previousMode);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('切换失败，已保持原来的连接')));
    }
  }

  void _showConnectionCenter() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: P.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '连接中心',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '切换连接不会退出账号。正在生成内容时建议等待完成后再切换。',
                style: TextStyle(color: P.textSecondary),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('远程连接'),
                subtitle: Text(
                  _connectionMode == 'public' ? '当前正在使用' : '通过官网连接，适合外出使用',
                ),
                trailing: _connectionMode == 'public'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : FilledButton.tonal(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _switchConnection('public');
                        },
                        child: const Text('切换'),
                      ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lan_outlined),
                title: const Text('本地连接'),
                subtitle: Text(
                  _connectionMode == 'lan'
                      ? '当前正在使用'
                      : _checkingLocal
                      ? '正在检查电脑…'
                      : _localAvailable
                      ? '本地电脑可用，通常速度更快'
                      : '当前未检测到本地电脑',
                ),
                trailing: _connectionMode == 'lan'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : FilledButton.tonal(
                        onPressed: _localAvailable
                            ? () {
                                Navigator.pop(sheetContext);
                                _switchConnection('lan');
                              }
                            : null,
                        child: const Text('切换'),
                      ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _checkLocalConnection();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新检测本地连接'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Polls social conversations and raises a system notification for new
  /// incoming messages. The first poll after launch only primes watermarks.
  Future<void> _pollSocial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('socialToken');
      if (token == null) return;
      // The social backend is centralized on the main domain regardless of
      // which dsh instance the login resolved to.
      final api = SocialApi(
        baseUrl: '$kDefaultServerUrl/social',
        basicUser: state.authUsername,
        basicPass: state.authPassword,
        token: token,
      );
      final conversations = await api.conversations();
      final raw = prefs.getString('msgWatermarks');
      final watermarks = <String, int>{
        if (raw != null)
          for (final entry in (jsonDecode(raw) as Map).entries)
            entry.key: (entry.value as num).toInt(),
      };
      var changed = false;
      for (final c in conversations) {
        final seen = watermarks[c.userId] ?? 0;
        if (c.lastTime > seen) {
          if (!_socialFirstPoll && c.unread > 0) {
            unawaited(
              NotificationService.instance.showMessage(
                c.userId,
                c.nickname,
                c.lastText,
              ),
            );
          }
          watermarks[c.userId] = c.lastTime;
          changed = true;
        }
      }
      final firstPoll = _socialFirstPoll;
      _socialFirstPoll = false;
      if (changed) {
        await prefs.setString('msgWatermarks', jsonEncode(watermarks));
      }
      // Friend requests: notify once per request id.
      final requests = await api.friendRequests();
      final seenRaw = prefs.getString('friendReqSeen') ?? '[]';
      final seen = <int>{
        for (final id in (jsonDecode(seenRaw) as List)) (id as num).toInt(),
      };
      final fresh = requests.where((r) => !seen.contains(r.id)).toList();
      if (fresh.isNotEmpty) {
        if (!firstPoll) {
          for (final request in fresh) {
            unawaited(
              NotificationService.instance.showFriendRequest(
                request.from.nickname,
              ),
            );
          }
        }
        seen.addAll(fresh.map((r) => r.id));
        await prefs.setString('friendReqSeen', jsonEncode(seen.toList()));
      }
    } catch (_) {
      // Poll again next tick.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      state.resyncAfterResume();
      unawaited(_checkLocalConnection());
      final pending = _pendingUpdate;
      if (pending != null) {
        _pendingUpdate = null;
        _updateFlowActive = false;
        _startUpdate(pending.checker, pending.info);
      }
    }
  }

  /// Starts the update flow: guides the one-time install-unknown-apps grant
  /// first when needed, then opens the download dialog.
  Future<void> _startUpdate(UpdateChecker checker, UpdateInfo info) async {
    if (_updateFlowActive) return;
    _updateFlowActive = true;
    if (!await checker.canInstall()) {
      if (!mounted) {
        _updateFlowActive = false;
        return;
      }
      _pendingUpdate = (checker: checker, info: info);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: P.cardAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.install_mobile_outlined,
                  size: 18,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 10),
              const Text('需要安装权限', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Text(
            '首次使用应用内更新,需要允许本应用"安装未知来源应用"。\n\n去设置打开后返回,会自动继续下载。',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: P.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _pendingUpdate = null;
                _updateFlowActive = false;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                checker.requestInstallPermission();
              },
              style: FilledButton.styleFrom(
                backgroundColor: P.accent,
                foregroundColor: P.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) {
      _updateFlowActive = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDownloadDialog(checker: checker, info: info),
    );
    _updateFlowActive = false;
  }

  /// Polls the release manifest once per home-page lifetime; [manual] checks
  /// (drawer entry) always run and report every outcome. Android-only: iOS
  /// distribution must go through the App Store / TestFlight (guideline 2.5.2).
  Future<void> _checkForUpdate({bool manual = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _updateCheckInFlight ||
        _updateFlowActive ||
        _updateDialogOpen) {
      return;
    }
    _updateCheckInFlight = true;
    try {
      await _performUpdateCheck(manual: manual);
    } finally {
      _updateCheckInFlight = false;
    }
  }

  Future<void> _performUpdateCheck({bool manual = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final checker = UpdateChecker(
      username: state.authUsername,
      password: state.authPassword,
    );
    final result = await checker.check(kUpdateManifestUrl);
    if (!mounted) return;
    final info = result.info;
    if (info == null) {
      if (manual) _toast('检查更新失败: ${result.error}');
      return;
    }
    final package = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(package.buildNumber) ?? 0;
    if (!mounted) return;
    if (info.versionCode <= currentCode) {
      if (manual) {
        _toast(
          '已是最新: 本机 v${package.version}+${package.buildNumber} · '
          '服务器 v${info.version}+${info.versionCode}',
        );
      }
      return;
    }
    setState(() => _availableUpdate = info);
    // Auto-checks prompt once per version per run; manual always prompts.
    if (manual || _updateDialogShownFor != info.versionCode) {
      _updateDialogShownFor = info.versionCode;
      await _showUpdateDialog(checker, info);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showUpdateDialog(UpdateChecker checker, UpdateInfo info) async {
    if (_updateDialogOpen || _updateFlowActive) return;
    _updateDialogOpen = true;
    var startUpdate = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => UpdateAvailableDialog(
        info: info,
        onUpdate: () {
          startUpdate = true;
          Navigator.of(dialogContext).pop();
        },
      ),
    );
    _updateDialogOpen = false;
    if (startUpdate && mounted) await _startUpdate(checker, info);
  }

  /// Shows the release notes once per app version after an update.
  Future<void> _maybeShowWhatsNew() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('lastSeenVersion') == kAppVersion) return;
    await prefs.setString('lastSeenVersion', kAppVersion);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => const WhatsNewDialog(),
    );
  }

  Future<void> _maybeShowQuickStart() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('quickStartShown') == true || !mounted) return;
    await prefs.setBool('quickStartShown', true);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const QuickStartSheet(),
    );
  }

  SessionRow? _selectedRow() {
    for (final row in state.sessions) {
      if (row.sessionId == state.selectedSessionId) return row;
    }
    return null;
  }

  void _maybeShowInteractions() {
    for (final approval in state.approvals) {
      if (_shownApprovals.add(approval.approvalId)) {
        unawaited(NotificationService.instance.showApproval(approval.toolName));
        final target = approval;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showApproval(target);
        });
        return; // one dialog at a time
      }
    }
    for (final question in state.questions) {
      if (_shownQuestions.add(question.rpcId)) {
        unawaited(NotificationService.instance.showQuestion());
        final target = question;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showQuestion(target);
        });
        return;
      }
    }
  }

  /// Shows a non-dismissible interaction dialog (approval/question) that also
  /// closes itself when the interaction is resolved from ANOTHER client (e.g.
  /// answered in the web GUI): [gone] reports the pending entry has left the
  /// state lists. The builder receives a [close] that must be used instead of
  /// a raw Navigator pop — answering notifies the state synchronously, which
  /// re-enters the auto-close listener, and only the latch keeps that from
  /// popping the page under the dialog.
  Future<void> _showInteraction({
    required bool Function() gone,
    required Widget Function(BuildContext context, VoidCallback close) builder,
  }) async {
    BuildContext? dialogContext;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
    }

    void onStateChanged() {
      if (gone()) close();
    }

    state.addListener(onStateChanged);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        // PopScope blocks the Android back button/gesture: a dismissed-but-
        // unanswered interaction stayed in the state lists with its id
        // already consumed by _shownApprovals/_shownQuestions, so it could
        // never be answered again.
        builder: (ctx) {
          dialogContext = ctx;
          return PopScope(canPop: false, child: builder(ctx, close));
        },
      );
    } finally {
      state.removeListener(onStateChanged);
    }
  }

  Future<void> _showApproval(PendingApproval approval) async {
    await _showInteraction(
      gone: () =>
          !state.approvals.any((a) => a.approvalId == approval.approvalId),
      builder: (dialogContext, close) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gpp_maybe_outlined, color: Colors.amber),
            SizedBox(width: 10),
            Text('审批请求'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: P.fillLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                approval.toolName,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            if (approval.reason != null && approval.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                approval.reason!,
                style: TextStyle(color: P.textSecondary, height: 1.4),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              close();
              state.answerApproval(approval, 'rejected');
            },
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () {
              close();
              state.answerApproval(approval, 'allowed-once');
            },
            child: const Text('允许一次'),
          ),
        ],
      ),
    );
    // Defensive: if the route went away without an answer (teardown paths
    // PopScope cannot cover), un-mark it so the next rebuild re-shows it.
    if (mounted &&
        state.approvals.any((a) => a.approvalId == approval.approvalId)) {
      _shownApprovals.remove(approval.approvalId);
      setState(() {});
    }
  }

  Future<void> _showQuestion(PendingQuestion question) async {
    await _showInteraction(
      gone: () => !state.questions.any((q) => q.rpcId == question.rpcId),
      builder: (dialogContext, close) =>
          QuestionDialog(state: state, pending: question, onClosed: close),
    );
    // Defensive re-show, mirroring _showApproval.
    if (mounted && state.questions.any((q) => q.rpcId == question.rpcId)) {
      _shownQuestions.remove(question.rpcId);
      setState(() {});
    }
  }

  Future<void> _renameDialog() async {
    final sessionId = state.selectedSessionId;
    if (sessionId == null) return;
    final controller = TextEditingController(text: _selectedRow()?.title ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '会话名称'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) {
      await state.renameSession(sessionId, result.trim());
    }
  }

  Future<void> _showModelPicker() async {
    await state.loadModels();
    if (!mounted || state.models == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ModelPickerSheet(state: state),
    );
  }

  /// New-session entry: inside a conversation the child inherits the current
  /// workspace directly; otherwise the directory picker sheet opens.
  void _newSession() {
    final row = _selectedRow();
    final cwd = row?.cwd;
    if (state.selectedSessionId != null && cwd != null && cwd.isNotEmpty) {
      state.createSession(cwd: cwd);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已在当前工作区新建会话'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _showNewSessionSheet();
  }

  void _showNewSessionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => NewSessionSheet(state: state),
    );
  }

  /// Empty-state suggestion chip: opens a default-workspace session and sends
  /// the suggested prompt right away.
  Future<void> _sendSuggestion(String text) async {
    await state.createSession();
    await state.sendPrompt(text);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authUser');
    await prefs.remove('authPass');
    await prefs.remove('serverUrl');
    state.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        _maybeShowInteractions();
        final levelUp = state.lastLevelUp;
        if (levelUp != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            state.clearLevelUp();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '🎉 升级啦! 已达到 Lv.${levelUp.level} · ${levelUp.title}(共 ${levelUp.count} 次对话)',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          });
        }
        final sessionId = state.selectedSessionId;
        if (sessionId != null && sessionId != _modelsLoadedFor) {
          _modelsLoadedFor = sessionId;
          unawaited(state.loadModels());
        }
        final row = _selectedRow();
        final title = row?.title?.isNotEmpty == true
            ? row!.title!
            : (sessionId == null ? 'xHarness' : '新会话');
        final subtitleParts = <String>[
          ?state.models?.label,
          if (state.syncingTail) '正在同步最新进度…',
          if (state.fillingHistoryGap) '正在补齐中间历史…',
          if (state.selectedRunning) '正在生成…',
        ];
        return Scaffold(
          drawer: SessionDrawer(
            state: state,
            theme: widget.theme,
            onLogout: _logout,
            onNewSession: _showNewSessionSheet,
            onCheckUpdate: () => _checkForUpdate(manual: true),
            onConnectionCenter: _showConnectionCenter,
            connectionMode: _connectionMode,
            localAvailable: _localAvailable,
            updateAvailable: _availableUpdate != null,
            socialBaseUrl: '$kDefaultServerUrl/social',
            connectionGuideBuilder: (_) => const ConnectionGuideSheet(),
            changelogBuilder: (_) => const ChangelogPage(),
          ),
          appBar: SessionHeader(
            state: state,
            title: title,
            subtitleParts: subtitleParts,
            onModelPicker: _showModelPicker,
            onNewSession: _newSession,
            onRename: _renameDialog,
            onRefresh: state.refreshSessions,
            onCheckUpdate: () => _checkForUpdate(manual: true),
            onLogout: _logout,
          ),
          body: Column(
            children: [
              StatsBar(state: state),
              Expanded(
                child: sessionId == null
                    ? _EmptyState(
                        onNewSession: _showNewSessionSheet,
                        onSuggestion: _sendSuggestion,
                      )
                    : ChatList(state: state),
              ),
              Composer(state: state),
            ],
          ),
        );
      },
    );
  }
}

/// Branded welcome shown when no session is selected, with quick-start
/// suggestion chips that open a session and send the prompt in one tap.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewSession, required this.onSuggestion});

  final VoidCallback onNewSession;

  /// Sends a suggestion as a fresh session's first prompt.
  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    (Icons.code, '帮我 review 一段代码'),
    (Icons.edit_note, '帮我写一份工作周报'),
    (Icons.lightbulb_outline, '给我三个副业点子'),
    (Icons.travel_explore, '规划一个周末短途旅行'),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 76),
            const SizedBox(height: 22),
            Text(
              '开始一个新的对话',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '在下方输入消息,或从左上角菜单选择历史会话',
              textAlign: TextAlign.center,
              style: TextStyle(color: P.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final (icon, label) in _suggestions)
                  Material(
                    color: P.card,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSuggestion(label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: P.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 15, color: P.accentLight),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: P.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            FilledButton.tonalIcon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add),
              label: const Text('新建会话'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Question dialog
// ---------------------------------------------------------------------------

class QuestionDialog extends StatefulWidget {
  const QuestionDialog({
    super.key,
    required this.state,
    required this.pending,
    this.onClosed,
  });

  final AppState state;
  final PendingQuestion pending;

  /// Close route owned by the interaction host (_showInteraction); when set,
  /// _submit uses it instead of a raw pop so the auto-close latch wins.
  final VoidCallback? onClosed;

  @override
  State<QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<QuestionDialog> {
  final Map<String, Set<String>> _selected = {};
  final Map<String, TextEditingController> _custom = {};

  @override
  void dispose() {
    for (final controller in _custom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _questionId(Map<String, dynamic> q) => q['id'] as String? ?? '';

  List<Map<String, dynamic>> _options(Map<String, dynamic> q) =>
      ((q['options'] as List?) ?? const [])
          .map((o) => (o as Map).cast<String, dynamic>())
          .toList();

  bool _multi(Map<String, dynamic> q) => q['multiSelect'] == true;

  TextEditingController _customFor(String id) =>
      _custom.putIfAbsent(id, TextEditingController.new);

  bool get _canSubmit {
    for (final q in widget.pending.questions) {
      final id = _questionId(q);
      final selected = _selected[id] ?? const <String>{};
      final custom = _custom[id]?.text.trim() ?? '';
      if (selected.isEmpty && custom.isEmpty) return false;
    }
    return true;
  }

  void _toggle(String id, String label, bool multi) {
    setState(() {
      final set = _selected.putIfAbsent(id, () => {});
      if (multi) {
        set.contains(label) ? set.remove(label) : set.add(label);
      } else {
        set
          ..clear()
          ..add(label);
      }
    });
  }

  void _submit() {
    final answers = <Map<String, dynamic>>[
      for (final q in widget.pending.questions)
        {
          'id': _questionId(q),
          'selected': (_selected[_questionId(q)] ?? const <String>{}).toList(),
          if ((_custom[_questionId(q)]?.text.trim() ?? '').isNotEmpty)
            'custom': _custom[_questionId(q)]!.text.trim(),
        },
    ];
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed();
    } else {
      Navigator.of(context).pop();
    }
    widget.state.answerQuestion(widget.pending, answers);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.quiz_outlined, color: P.accentLight),
          SizedBox(width: 10),
          Text('请回答'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.pending.questions.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _questionView(widget.pending.questions[i]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('提交'),
        ),
      ],
    );
  }

  Widget _questionView(Map<String, dynamic> q) {
    final id = _questionId(q);
    final header = q['header'] as String?;
    final question = q['question'] as String? ?? '';
    final detail = q['detail'] as String?;
    final options = _options(q);
    final multi = _multi(q);
    final selected = _selected[id] ?? const <String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null && header.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              header,
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                color: P.accentLight,
              ),
            ),
          ),
        Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
        if (detail != null && detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              detail,
              style: TextStyle(
                fontSize: 12.5,
                color: P.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        if (multi)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '可多选',
              style: TextStyle(fontSize: 11, color: P.textTertiary),
            ),
          ),
        const SizedBox(height: 10),
        for (final option in options)
          _optionTile(
            id,
            option,
            multi,
            selected.contains(option['label'] as String? ?? ''),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextField(
            controller: _customFor(id),
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: options.isEmpty ? '输入回答' : '其他(可选)',
              hintStyle: TextStyle(fontSize: 13, color: P.textTertiary),
              isDense: true,
              filled: true,
              fillColor: P.fillSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: P.fillLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: P.fillLight),
              ),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
    String id,
    Map<String, dynamic> option,
    bool multi,
    bool selected,
  ) {
    final label = option['label'] as String? ?? '';
    final description = option['description'] as String?;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggle(id, label, multi),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.18) : P.fillSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? primary.withValues(alpha: 0.7) : P.fillMedium,
            ),
          ),
          child: Row(
            children: [
              Icon(
                multi
                    ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                    : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off),
                size: 20,
                color: selected ? primary : P.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 14)),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description,
                          style: TextStyle(fontSize: 12, color: P.textTertiary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composer
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Stats bar
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Slash commands
// ---------------------------------------------------------------------------

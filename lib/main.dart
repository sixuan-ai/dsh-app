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
import 'connection_center.dart';
import 'brand_mark.dart';
import 'quick_start.dart';
import 'question_dialog.dart';
import 'src/notifications.dart';
import 'src/protocol.dart';
import 'src/social.dart';
import 'update_dialogs.dart';
import 'src/theme.dart';
import 'src/updater.dart';
import 'home_view.dart';
import 'session_drawer.dart';
import 'model_picker.dart';
import 'changelog_view.dart';
import 'new_session_sheet.dart';
import 'state.dart';

/// Built-in server endpoint (frp tunnel → auth proxy → dsh web).
const kDefaultServerUrl = 'https://dsh.ainotex.com';

/// Direct Shenzhen relay endpoint (nginx → frps → auth proxy), no Cloudflare.
const kDirectServerUrl = 'https://sz.ainotex.com';

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
  bool _levelUpScheduled = false;

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
    state.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWhatsNew();
      _maybeShowQuickStart();
      _checkForUpdate();
      _onStateChanged();
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
    state.removeListener(_onStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onStateChanged() {
    _maybeShowInteractions();
    final sessionId = state.selectedSessionId;
    if (sessionId != null && sessionId != _modelsLoadedFor) {
      _modelsLoadedFor = sessionId;
      unawaited(state.loadModels());
    }
    if (state.lastLevelUp != null && !_levelUpScheduled) {
      _levelUpScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _levelUpScheduled = false;
        if (!mounted) return;
        final levelUp = state.lastLevelUp;
        if (levelUp == null) return;
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
    var target = switch (mode) {
      'lan' => _localUrl,
      // Direct Shenzhen relay: same account and credentials, no Cloudflare.
      'direct' => kDirectServerUrl,
      _ => _remoteUrl,
    };
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
        SnackBar(
          content: Text(switch (mode) {
            'lan' => '已切换到本地连接',
            'direct' => '已切换到深圳直连',
            _ => '已切换到远程连接',
          }),
        ),
      );
    } else {
      setState(() => _connectionMode = previousMode);
      final reason = state.lastProbeError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason == null ? '切换失败，已保持原来的连接' : '切换失败: $reason',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
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
      builder: (_) => ConnectionCenterSheet(
        connectionMode: _connectionMode,
        checkingLocal: _checkingLocal,
        localAvailable: _localAvailable,
        onSwitchRemote: () => _switchConnection('public'),
        onSwitchLocal: () => _switchConnection('lan'),
        onSwitchDirect: () => _switchConnection('direct'),
        onRefreshLocal: _checkLocalConnection,
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
    return HomeView(
      state: state,
      drawerBuilder: (context) => SessionDrawer(
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
      onModelPicker: _showModelPicker,
      onNewSession: _newSession,
      onRename: _renameDialog,
      onRefresh: state.refreshSessions,
      onCheckUpdate: () => _checkForUpdate(manual: true),
      onLogout: _logout,
      onSuggestion: _sendSuggestion,
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

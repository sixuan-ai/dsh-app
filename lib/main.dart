/// xHarness — Flutter client for the DeepSeek Harness web API.
///
/// Server URL is a built-in default; the user only ever enters credentials.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/changelog.dart';
import 'src/l10n.dart';
import 'src/lan_discovery.dart';
import 'login_view.dart';
import 'connection_guide.dart';
import 'connection_center.dart';
import 'brand_mark.dart';
import 'quick_start.dart';
import 'question_dialog.dart';
import 'src/notifications.dart';
import 'src/protocol.dart';
import 'src/native_probe.dart';
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
const kDirectServerUrl = 'https://dsh.qxrobot.com';

/// Legacy Shenzhen entry retained only as a fallback during migration.
const kDirectServerFallbackUrl = 'https://sz.ainotex.com';

const _nativeNetworkChannel = MethodChannel(
  'dev.dsh.dsh_mobile/native_network',
);

/// Maps the live server URL back to the connection-mode key used across the
/// app ('lan' / 'direct' / 'public'). The mode is derived from the URL the
/// socket actually holds — never from a separately persisted flag — so the
/// connection center always agrees with where the app is really connected.
String connectionModeForUrl(String serverUrl, {String? localUrl}) {
  if (serverUrl.isNotEmpty && serverUrl == localUrl) return 'lan';
  if (serverUrl == kDirectServerUrl || serverUrl == kDirectServerFallbackUrl) {
    return 'direct';
  }
  return 'public';
}

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
  final LanguageController language = LanguageController();
  bool _restored = false;
  bool _hasCreds = false;

  @override
  void initState() {
    super.initState();
    theme.addListener(_onAppearanceChanged);
    language.addListener(_onAppearanceChanged);
    unawaited(theme.load());
    unawaited(language.load());
    _restore();
  }

  void _onAppearanceChanged() => setState(() {});

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('authUser');
    final pass = prefs.getString('authPass');
    if (user != null && pass != null && user.isNotEmpty) {
      _hasCreds = true;
      // Local history is independent of the computer service. Restore it
      // first so a returning user never waits on a transient network outage
      // just to enter the app.
      await appState.restoreCachedSnapshot(username: user, password: pass);
      // The instance URL was resolved through the directory at login;
      // reconnect to it directly (no directory round-trip at boot).
      final mode = prefs.getString('connectionMode') ?? 'public';
      final serverUrl = mode == 'lan'
          ? (prefs.getString('lanServerUrl') ??
                prefs.getString('serverUrl') ??
                kDefaultServerUrl)
          : (prefs.getString('serverUrl') ?? kDefaultServerUrl);
      if (mounted) setState(() => _restored = true);
      unawaited(appState.connect(serverUrl, username: user, password: pass));
      return;
    }
    if (mounted) setState(() => _restored = true);
  }

  @override
  void dispose() {
    theme.removeListener(_onAppearanceChanged);
    theme.dispose();
    language.removeListener(_onAppearanceChanged);
    language.dispose();
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Publish the active palette and strings before the tree reads them; an
    // appearance change rebuilds from this root, so every P/S read observes
    // the new theme and language.
    P = theme.palette;
    S = language.s;
    return MaterialApp(
      title: 'xHarness',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(P),
      locale: language.locale,
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          if (!_restored) return const _Splash(label: '正在启动…');
          if (appState.connected ||
              (_hasCreds && !appState.requiresAuthentication)) {
            return HomePage(state: appState, theme: theme, language: language);
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
  const HomePage({
    super.key,
    required this.state,
    required this.theme,
    required this.language,
  });

  final AppState state;
  final ThemeController theme;
  final LanguageController language;

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
  String? _remoteUrl;

  /// Route the app is actually on, derived from the live server URL so the
  /// connection center can never disagree with the socket the app holds.
  /// A separately persisted flag can go stale (a switch tears HomePage down
  /// and rebuilds it mid-reconnect), so the URL is the source of truth.
  String get _connectionMode =>
      connectionModeForUrl(state.serverUrl, localUrl: _localUrl);

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(_onStateChanged);
    unawaited(_restoreConnectionState());
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

  /// Loads the persisted route targets right away so the derived mode and the
  /// public-switch destination are correct even before the LAN probe finishes.
  Future<void> _restoreConnectionState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _remoteUrl = prefs.getString('remoteServerUrl');
      _localUrl = prefs.getString('lanServerUrl');
    });
  }

  Future<void> _checkLocalConnection() async {
    if (_checkingLocal || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final localUrl = prefs.getString('lanServerUrl');
    final remoteUrl = prefs.getString('remoteServerUrl');
    setState(() {
      _localUrl = localUrl;
      _remoteUrl = remoteUrl;
    });
    if (localUrl == null || localUrl.isEmpty) {
      if (mounted) setState(() => _localAvailable = false);
      return;
    }
    setState(() {
      _checkingLocal = true;
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

  Future<Map<String, dynamic>?> _nativeProbe(String url) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final value = await _nativeNetworkChannel.invokeMethod<dynamic>(
        'probeDsh',
        {
          'url': url,
          'username': state.authUsername,
          'password': state.authPassword,
        },
      );
      if (value is Map) return value.cast<String, dynamic>();
    } on PlatformException catch (error) {
      return {'ok': false, 'errorType': error.code, 'error': error.message};
    } on MissingPluginException {
      return {
        'ok': false,
        'errorType': 'missing-plugin',
        'error': 'native channel unavailable',
      };
    }
    return null;
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
      ).showSnackBar(SnackBar(content: Text(S.noConnectionTarget)));
      return;
    }
    var ok = false;
    String? nativeProbeSummary;
    if (mode == 'direct') {
      // Prefer the qxrobot hostname; retain the old ainotex hostname for
      // rollback compatibility while DNS and installed clients converge.
      for (final candidate in const [
        kDirectServerUrl,
        kDirectServerFallbackUrl,
      ]) {
        if (await state.switchConnection(candidate)) {
          target = candidate;
          ok = true;
          break;
        }
      }
      if (!ok) {
        final nativeResult = await _nativeProbe(kDirectServerUrl);
        if (nativeResult != null) {
          nativeProbeSummary = formatNativeProbeResult(nativeResult);
        }
      }
    } else {
      ok = await state.switchConnection(target);
    }
    if (!mounted) return;
    if (ok) {
      await prefs.setString('connectionMode', mode);
      await prefs.setString('serverUrl', target!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (mode) {
            'lan' => S.switchedToLocal,
            'direct' => S.switchedToSz,
            _ => S.switchedToRemote,
          }),
        ),
      );
    } else {
      final reason = state.lastProbeError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nativeProbeSummary ??
                (reason == null
                    ? S.switchFailedKeep
                    : '${S.switchFailed}$reason'),
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
        localUrl: _localUrl,
        onSwitchRemote: () => _switchConnection('public'),
        onSwitchLocal: () => _switchConnection('lan'),
        onSwitchDirect: () => _switchConnection('direct'),
        onRefreshLocal: _checkLocalConnection,
        onSetLocalAddress: _setLocalAddress,
        onAutoSearchLocal: _autoSearchLocal,
      ),
    );
  }

  /// Runs mDNS discovery and lets the user pick the local DSH host.
  Future<void> _autoSearchLocal() async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _LanSearchSheet(
        onPick: (device) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('lanServerUrl', device.url);
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          await _checkLocalConnection();
        },
      ),
    );
  }

  /// Edits the LAN address of the local computer, persists it, and probes it.
  Future<void> _setLocalAddress() async {
    final controller = TextEditingController(text: _localUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.localAddressTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: S.localAddressHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(S.save),
          ),
        ],
      ),
    );
    controller.dispose();
    final url = result?.trim() ?? '';
    if (url.isEmpty || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lanServerUrl', url);
    await _checkLocalConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_localAvailable ? S.localAddressSaved : S.localDescNone),
        duration: const Duration(seconds: 2),
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
        language: widget.language,
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
      onRetryConnection: () => unawaited(state.retryConnection()),
      onConnectionCenter: _showConnectionCenter,
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

// ---------------------------------------------------------------------------
// LAN discovery sheet
// ---------------------------------------------------------------------------

/// mDNS search sheet: discovers DSH hosts on the LAN and lets the user pick
/// one. [discover] is injectable for tests.
class _LanSearchSheet extends StatefulWidget {
  const _LanSearchSheet({required this.onPick});

  final ValueChanged<LanDshDevice> onPick;

  @override
  State<_LanSearchSheet> createState() => _LanSearchSheetState();
}

class _LanSearchSheetState extends State<_LanSearchSheet> {
  List<LanDshDevice>? _devices;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _devices = null);
    final devices = await discoverLocalDsh();
    if (mounted) setState(() => _devices = devices);
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.autoSearchLocal,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (devices == null)
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    S.searchingDevices,
                    style: TextStyle(color: P.textSecondary),
                  ),
                ],
              )
            else if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  S.noDeviceFound,
                  style: TextStyle(color: P.textTertiary, fontSize: 13),
                ),
              )
            else ...[
              Text(
                S.deviceList,
                style: TextStyle(color: P.textTertiary, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              for (final device in devices)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.computer, color: P.accentLight),
                    title: Text(device.name),
                    subtitle: Text(
                      device.url,
                      style: TextStyle(
                        fontSize: 12,
                        color: P.textTertiary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => widget.onPick(device),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

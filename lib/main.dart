/// DSH Mobile — Flutter client for the DeepSeek Harness web API.
///
/// Server URL is a built-in default; the user only ever enters credentials.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/changelog.dart';
import 'src/updater.dart';
import 'state.dart';

/// Built-in server endpoint (frp tunnel → auth proxy → dsh web).
const kDefaultServerUrl = 'https://dsh.ainotex.com';

/// Release manifest polled by the in-app updater. During development this can
/// point at a LAN server (e.g. http://192.168.1.5:8000/latest.json) for fast
/// download tests; production uses the public domain.
const kUpdateManifestUrl = 'https://dsh.ainotex.com/releases/latest.json';

/// Brand accent gradient used for bubbles, buttons, and the logo.
const kBrandGradient = LinearGradient(
  colors: [Color(0xFF4D6BFE), Color(0xFF7C5CFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const _kBg = Color(0xFF0E1220);
const _kCard = Color(0xFF171D2E);
const _kCode = Color(0xFF11182B);

void main() => runApp(const DshApp());

ThemeData _buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4D6BFE),
    brightness: Brightness.dark,
  ).copyWith(surface: _kBg);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF141A2B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: _kBg),
    dividerTheme: const DividerThemeData(color: Colors.white12, thickness: 0.5),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class DshApp extends StatefulWidget {
  const DshApp({super.key});

  @override
  State<DshApp> createState() => _DshAppState();
}

class _DshAppState extends State<DshApp> {
  final AppState appState = AppState();
  bool _restored = false;
  bool _hasCreds = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('authUser');
    final pass = prefs.getString('authPass');
    if (user != null && pass != null && user.isNotEmpty) {
      _hasCreds = true;
      unawaited(appState.connect(kDefaultServerUrl, username: user, password: pass));
    }
    if (mounted) setState(() => _restored = true);
  }

  @override
  void dispose() {
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH Mobile',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          if (!_restored) return const _Splash(label: '正在启动…');
          if (appState.connected) return HomePage(state: appState);
          if (_hasCreds && appState.connecting) {
            return const _Splash(label: '正在连接服务器…');
          }
          return ServerSetupPage(state: appState);
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
            const _BrandMark(size: 76),
            const SizedBox(height: 20),
            Text(label, style: const TextStyle(color: Colors.white54)),
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
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4D6BFE).withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.5),
    );
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({super.key, required this.state});

  final AppState state;

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('authUser');
    if (user != null && mounted) setState(() => _user.text = user);
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final user = _user.text.trim();
    final pass = _pass.text;
    if (user.isEmpty || pass.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authUser', user);
    await prefs.setString('authPass', pass);
    await widget.state.connect(kDefaultServerUrl, username: user, password: pass);
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(kDefaultServerUrl).host;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0E1220), Color(0xFF131A33), Color(0xFF1B1440)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedBuilder(
                  animation: widget.state,
                  builder: (context, _) {
                    final error = widget.state.connectionError;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _BrandMark(size: 84),
                        const SizedBox(height: 20),
                        Text(
                          'DSH Mobile',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text('连接到你的 DeepSeek Harness',
                            style: TextStyle(color: Colors.white54)),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: _user,
                                autofillHints: const [AutofillHints.username],
                                decoration: _loginDecoration('用户名', Icons.person_outline),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pass,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _connect(),
                                decoration: _loginDecoration('密码', Icons.lock_outline),
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.red.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: Colors.redAccent, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '连接失败: $error',
                                          style: const TextStyle(
                                              color: Colors.redAccent, fontSize: 12.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              _GradientButton(
                                label: '连接',
                                loading: widget.state.connecting,
                                onPressed: widget.state.connecting ? null : _connect,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.dns_outlined,
                                size: 13, color: Colors.white30),
                            const SizedBox(width: 6),
                            Text(host,
                                style: const TextStyle(
                                    color: Colors.white30, fontSize: 12)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _loginDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF4D6BFE), width: 1.5),
      ),
    );
  }
}

/// Full-width gradient action button with loading state.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled ? kBrandGradient : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Set<String> _shownApprovals = {};
  final Set<String> _shownQuestions = {};
  String? _modelsLoadedFor;
  bool _updateChecked = false;

  /// Update deferred while the user grants install-unknown-apps in settings;
  /// resumed lifecycle restarts it automatically.
  ({UpdateChecker checker, UpdateInfo info})? _pendingUpdate;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWhatsNew();
      _checkForUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      final pending = _pendingUpdate;
      if (pending != null) {
        _pendingUpdate = null;
        _startUpdate(pending.checker, pending.info);
      }
    }
  }

  /// Starts the update flow: guides the one-time install-unknown-apps grant
  /// first when needed, then opens the download dialog.
  Future<void> _startUpdate(UpdateChecker checker, UpdateInfo info) async {
    if (!await checker.canInstall()) {
      if (!mounted) return;
      _pendingUpdate = (checker: checker, info: info);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要安装权限'),
          content: const Text(
              '首次使用应用内更新,需要允许本应用"安装未知来源应用"。\n\n去设置打开后返回,会自动继续下载。'),
          actions: [
            TextButton(
              onPressed: () {
                _pendingUpdate = null;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                checker.requestInstallPermission();
              },
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDownloadDialog(checker: checker, info: info),
    );
  }

  /// Polls the release manifest once per home-page lifetime; [manual] checks
  /// (drawer entry) always run and report every outcome. Android-only: iOS
  /// distribution must go through the App Store / TestFlight (guideline 2.5.2).
  Future<void> _checkForUpdate({bool manual = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!manual) {
      if (_updateChecked) return;
      _updateChecked = true;
    }
    final checker = UpdateChecker(
        username: state.authUsername, password: state.authPassword);
    final info = await checker.fetchManifest(kUpdateManifestUrl);
    if (!mounted) return;
    if (info == null) {
      if (manual) _toast('检查更新失败,请稍后重试');
      return;
    }
    final package = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(package.buildNumber) ?? 0;
    if (!mounted) return;
    if (info.versionCode <= currentCode) {
      if (manual) _toast('已是最新版本 (v${package.version})');
      return;
    }
    _showUpdateDialog(checker, info);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showUpdateDialog(UpdateChecker checker, UpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update_alt, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('发现新版本'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('v${info.version}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (info.size != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_fmtBytes(info.size!),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white38)),
              ),
            if (info.notes != null && info.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(info.notes!,
                    style: const TextStyle(
                        fontSize: 13, height: 1.5, color: Colors.white70)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _startUpdate(checker, info);
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('立即更新'),
          ),
        ],
      ),
    );
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

  SessionRow? _selectedRow() {
    for (final row in state.sessions) {
      if (row.sessionId == state.selectedSessionId) return row;
    }
    return null;
  }

  void _maybeShowInteractions() {
    for (final approval in state.approvals) {
      if (_shownApprovals.add(approval.approvalId)) {
        final target = approval;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showApproval(target);
        });
        return; // one dialog at a time
      }
    }
    for (final question in state.questions) {
      if (_shownQuestions.add(question.rpcId)) {
        final target = question;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showQuestion(target);
        });
        return;
      }
    }
  }

  Future<void> _showApproval(PendingApproval approval) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
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
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(approval.toolName,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
            if (approval.reason != null && approval.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(approval.reason!,
                  style: const TextStyle(color: Colors.white70, height: 1.4)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              state.answerApproval(approval, 'rejected');
              Navigator.of(dialogContext).pop();
            },
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () {
              state.answerApproval(approval, 'allowed-once');
              Navigator.of(dialogContext).pop();
            },
            child: const Text('允许一次'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuestion(PendingQuestion question) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          QuestionDialog(state: state, pending: question),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已在当前工作区新建会话'),
        duration: Duration(seconds: 2),
      ));
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authUser');
    await prefs.remove('authPass');
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '🎉 升级啦! 已达到 Lv.${levelUp.level} · ${levelUp.title}(共 ${levelUp.count} 次对话)'),
              duration: const Duration(seconds: 4),
            ));
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
            : (sessionId == null ? 'DSH Mobile' : '新会话');
        return Scaffold(
          drawer: SessionDrawer(
            state: state,
            onLogout: _logout,
            onNewSession: _showNewSessionSheet,
            onCheckUpdate: () => _checkForUpdate(manual: true),
          ),
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(
                  child: Text(title, overflow: TextOverflow.ellipsis),
                ),
                if (state.selectedRunning) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            actions: [
              if (sessionId != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: TextButton.icon(
                    onPressed: state.loadingModels ? null : _showModelPicker,
                    icon: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: Text(
                      state.models?.label ?? '模型',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              IconButton(
                tooltip: '新建会话',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: _newSession,
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      _renameDialog();
                    case 'refresh':
                      state.refreshSessions();
                    case 'logout':
                      _logout();
                  }
                },
                itemBuilder: (context) => [
                  if (sessionId != null)
                    const PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline),
                        title: Text('重命名会话'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('刷新列表'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('退出登录'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              StatsBar(state: state),
              Expanded(
                child: sessionId == null
                    ? _EmptyState(onNewSession: _showNewSessionSheet)
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

/// Placeholder shown when no session is selected.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewSession});

  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BrandMark(size: 72),
          const SizedBox(height: 20),
          Text('开始一个新的对话',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('在下方输入消息,或从左上角菜单选择历史会话',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: onNewSession,
            icon: const Icon(Icons.add),
            label: const Text('新建会话'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session drawer
// ---------------------------------------------------------------------------

class SessionDrawer extends StatefulWidget {
  const SessionDrawer({
    super.key,
    required this.state,
    required this.onLogout,
    required this.onNewSession,
    required this.onCheckUpdate,
  });

  final AppState state;
  final VoidCallback onLogout;

  /// Opens the new-session directory picker (HomePage owns the context).
  final VoidCallback onNewSession;

  /// Runs a manual update check (HomePage owns the context).
  final VoidCallback onCheckUpdate;

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  /// Workspace keys (cwd) the user collapsed; persisted across launches.
  final Set<String> _collapsed = {};

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  Future<void> _loadCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('collapsedWorkspaces');
    if (saved != null && mounted) {
      setState(() => _collapsed.addAll(saved));
    }
  }

  Future<void> _toggleCollapsed(String key) async {
    setState(() {
      _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('collapsedWorkspaces', _collapsed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(state.serverUrl.isEmpty ? kDefaultServerUrl : state.serverUrl).host;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: kBrandGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text('DSH Mobile',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.dns_outlined,
                          size: 12, color: Colors.white70),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(host,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${state.sessions.length} 个会话',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 10),
                  _LevelBadge(level: state.userLevel),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onNewSession();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建会话'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _groupedSessionTiles(context),
              ),
            ),
            const Divider(height: 1),
            // OTA 自更新仅 Android;iOS 分发必须走 App Store / TestFlight。
            if (defaultTargetPlatform == TargetPlatform.android)
              ListTile(
                leading: const Icon(Icons.system_update_alt, size: 20),
                title: const Text('检查更新', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onCheckUpdate();
                },
              ),
            ListTile(
              leading: const Icon(Icons.new_releases_outlined, size: 20),
              title: const Text('更新日志', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const ChangelogPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, size: 20),
              title: const Text('退出登录', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.of(context).pop();
                widget.onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }
  /// Groups sessions by workspace directory (cwd), mirroring the web client;
  /// sessions without one collect in an 未分组 section at the end.
  List<Widget> _groupedSessionTiles(BuildContext context) {
    final groups = <String, List<SessionRow>>{};
    for (final row in state.sessions) {
      groups.putIfAbsent(row.cwd ?? '', () => []).add(row);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        final aTime = groups[a]!.map((r) => r.updatedAt).fold(0, math.max);
        final bTime = groups[b]!.map((r) => r.updatedAt).fold(0, math.max);
        return bTime.compareTo(aTime);
      });
    final tiles = <Widget>[];
    for (final key in keys) {
      final rows = groups[key]!;
      tiles.add(_workspaceHeader(key, rows.length));
      if (!_collapsed.contains(key)) {
        for (final row in rows) {
          tiles.add(_sessionTile(context, row));
        }
      }
    }
    return tiles;
  }

  Widget _workspaceHeader(String cwd, int count) {
    final parts = cwd.split('/').where((s) => s.isNotEmpty).toList();
    final name = cwd.isEmpty ? '未分组' : (parts.isEmpty ? cwd : parts.last);
    final collapsed = _collapsed.contains(cwd);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleCollapsed(cwd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Icon(
                collapsed
                    ? Icons.keyboard_arrow_right
                    : Icons.keyboard_arrow_down,
                size: 16,
                color: const Color(0xFF8FA6FF),
              ),
              const SizedBox(width: 2),
              Icon(
                cwd.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
                size: 14,
                color: const Color(0xFF8FA6FF),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: cwd.isEmpty ? '未分组' : cwd,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.4,
                      color: Color(0xFF8FA6FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text('$count',
                  style: const TextStyle(fontSize: 11, color: Colors.white30)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(BuildContext context, SessionRow row) {
    final selected = row.sessionId == state.selectedSessionId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          dense: true,
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: row.running ? Colors.greenAccent : Colors.white24,
            ),
          ),
          title: Text(
            row.title?.isNotEmpty == true ? row.title! : '新会话',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(_timeAgo(row.updatedAt),
              style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
          onTap: () {
            Navigator.of(context).pop();
            state.openSession(row.sessionId);
          },
        ),
      ),
    );
  }
}

/// Level badge with progress bar shown in the drawer header; taps open the
/// level rules dialog.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final UserLevel level;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showLevelRules(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.military_tech,
                    size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  'Lv.${level.level} · ${level.title}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text('${level.count} 次对话',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: level.progress,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.amber),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                level.next == null
                    ? '已达最高等级'
                    : '再对话 ${level.remaining} 次升至 Lv.${level.level + 1}',
                style: const TextStyle(color: Colors.white60, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLevelRules(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.military_tech, color: Colors.amber),
            SizedBox(width: 8),
            Text('等级规则'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '每发送一条消息计 1 次对话,累计达到阈值即可升级。计数保存在本机。',
                  style: TextStyle(fontSize: 12.5, color: Colors.white54),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < levelThresholds.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          i + 1 <= level.level
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 14,
                          color: i + 1 <= level.level
                              ? Colors.amber
                              : Colors.white24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lv.${i + 1} · ${levelTitles[i]}',
                            style: TextStyle(
                              fontSize: 13,
                              color: i + 1 == level.level
                                  ? Colors.amber
                                  : Colors.white70,
                              fontWeight: i + 1 == level.level
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Text('≥ ${levelThresholds[i]} 次',
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.white38)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// Relative timestamp for session rows.
String _timeAgo(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final mm = time.month.toString().padLeft(2, '0');
  final dd = time.day.toString().padLeft(2, '0');
  return '${time.year}-$mm-$dd';
}

// ---------------------------------------------------------------------------
// Chat list and items
// ---------------------------------------------------------------------------

class ChatList extends StatefulWidget {
  const ChatList({super.key, required this.state});

  final AppState state;

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  final ScrollController _controller = ScrollController();
  int _lastCount = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _nearBottom {
    if (!_controller.hasClients) return true;
    final position = _controller.position;
    return position.maxScrollExtent - position.pixels < 240;
  }

  void _maybeScroll() {
    final count = widget.state.items.length;
    final changed = count != _lastCount;
    final streaming = widget.state.selectedStreaming;
    if ((changed || streaming) && _nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      });
    }
    _lastCount = count;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    _maybeScroll();
    if (state.items.isEmpty) {
      if (state.loadingHistory) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(
        child: Text('发送消息开始对话', style: TextStyle(color: Colors.white38)),
      );
    }
    final extra = state.hasMoreHistory ? 1 : 0;
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.items.length + extra,
      itemBuilder: (context, index) {
        if (index < extra) {
          return Center(
            child: TextButton.icon(
              onPressed: state.loadingHistory
                  ? null
                  : () =>
                      state.loadHistory(state.selectedSessionId!, older: true),
              icon: state.loadingHistory
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.history, size: 16),
              label: const Text('加载更早的消息'),
            ),
          );
        }
        final item = state.items[index - extra];
        return ChatItemView(key: ValueKey(item.id), item: item);
      },
    );
  }
}

class ChatItemView extends StatelessWidget {
  const ChatItemView({super.key, required this.item});

  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case ChatItemKind.user:
        return _UserBubble(item: item);
      case ChatItemKind.assistant:
        return _AssistantMessage(item: item);
      case ChatItemKind.tool:
        return ToolCard(item: item);
      case ChatItemKind.notice:
        return _NoticeCard(item: item);
    }
  }
}

/// Right-aligned gradient user bubble.
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item});

  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(left: 56, right: 12, top: 5, bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: kBrandGradient,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4D6BFE).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Opacity(
            opacity: item.provisional ? 0.65 : 1,
            child: SelectableText(
              item.text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15.5, height: 1.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width assistant message with avatar and markdown body.
class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.item});

  final ChatItem item;

  bool get _streaming => item.id.startsWith('stream-');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final block in item.blocks) {
      if (block.type == 'reasoning') {
        children.add(_ReasoningCard(text: block.text, streaming: _streaming));
      } else if (block.text.trim().isNotEmpty || !_streaming) {
        children.add(
          MarkdownBody(
            data: block.text,
            selectable: true,
            styleSheet: _markdownStyle(context),
          ),
        );
      }
    }
    if (_streaming) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: _TypingDots(),
      ));
    }
    if (item.interrupted) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: _MiniChip(
            icon: Icons.stop_circle_outlined, label: '已中断', color: Colors.orange),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.circular(9),
            ),
            child:
                const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final base = TextStyle(
    color: scheme.onSurface.withValues(alpha: 0.92),
    fontSize: 15.5,
    height: 1.55,
  );
  return MarkdownStyleSheet(
    p: base,
    h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
    h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.bold),
    h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    h4: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    listBullet: base,
    strong: base.copyWith(fontWeight: FontWeight.bold),
    em: base.copyWith(fontStyle: FontStyle.italic),
    a: base.copyWith(color: const Color(0xFF8FA6FF)),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      color: const Color(0xFFA8C7FA),
      backgroundColor: _kCode,
    ),
    codeblockDecoration: BoxDecoration(
      color: _kCode,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: base.copyWith(color: Colors.white60),
    blockquoteDecoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(8),
      border: const Border(
        left: BorderSide(color: Color(0xFF4D6BFE), width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    tableBorder: TableBorder.all(color: Colors.white24, width: 0.5),
    tableHead: base.copyWith(fontWeight: FontWeight.bold),
    tableBody: base.copyWith(fontSize: 14),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
    ),
  );
}

/// Animated three-dot streaming indicator.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = _controller.value * 2 * math.pi + i * (2 * math.pi / 3);
            final opacity = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(phase));
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Collapsible reasoning block.
class _ReasoningCard extends StatefulWidget {
  const _ReasoningCard({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  late bool _expanded = widget.streaming;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.psychology_alt_outlined,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text(
                    widget.streaming ? '正在思考…' : '思考过程',
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.amber,
                        fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.amber.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                widget.text,
                style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white54,
                    fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small label chip used for message metadata.
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tool cards
// ---------------------------------------------------------------------------

class ToolCard extends StatefulWidget {
  const ToolCard({super.key, required this.item});

  final ChatItem item;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _expanded = false;

  Color get _statusColor {
    if (!widget.item.completed) return Colors.amber;
    if (widget.item.resultIsError) return Colors.redAccent;
    return Colors.greenAccent;
  }

  String get _statusLabel {
    if (!widget.item.completed) return '运行中';
    if (widget.item.resultIsError) return '失败';
    return '完成';
  }

  IconData get _icon {
    final name = widget.item.name.toLowerCase();
    if (name.contains('bash') ||
        name.contains('shell') ||
        name.contains('terminal')) {
      return Icons.terminal_rounded;
    }
    if (name.contains('read')) return Icons.description_outlined;
    if (name.contains('edit') || name.contains('write')) {
      return Icons.edit_note;
    }
    if (name.contains('grep') ||
        name.contains('glob') ||
        name.contains('search')) {
      return Icons.search;
    }
    if (name.contains('web') || name.contains('fetch')) return Icons.public;
    if (name.contains('todo')) return Icons.checklist;
    if (name.contains('agent')) return Icons.smart_toy_outlined;
    if (name.contains('skill')) return Icons.auto_awesome;
    return Icons.build_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: _statusColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        child: Row(
                          children: [
                            Icon(_icon, size: 16, color: Colors.white54),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MiniChip(
                              icon: item.completed
                                  ? (item.resultIsError
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline)
                                  : Icons.hourglass_top,
                              label: _statusLabel,
                              color: _statusColor,
                            ),
                            const Spacer(),
                            Icon(
                              _expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: Colors.white38,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expanded) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.arguments.isNotEmpty)
                              _codeSection(
                                  '参数', _truncate(summarizeArguments(item.arguments))),
                            if (item.resultText != null) ...[
                              const SizedBox(height: 10),
                              _codeSection(
                                item.resultIsError ? '错误' : '结果',
                                _truncate(item.resultText!),
                                isError: item.resultIsError,
                              ),
                            ],
                            if (!item.completed)
                              const Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('等待结果…',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white38)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeSection(String label, String content, {bool isError = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                color: isError ? Colors.redAccent : Colors.white38)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kCode,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isError
                  ? Colors.red.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: isError ? Colors.redAccent.withValues(alpha: 0.9) : Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  String _truncate(String text, [int max = 4000]) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n… (已截断)';
  }
}

/// System notice row (todo lists, errors, agent notices).
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.item});

  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isError ? Colors.redAccent : Colors.white38;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: item.isError
            ? Colors.red.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isError
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isError ? Icons.error_outline : Icons.checklist_rtl,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Question dialog
// ---------------------------------------------------------------------------

class QuestionDialog extends StatefulWidget {
  const QuestionDialog({super.key, required this.state, required this.pending});

  final AppState state;
  final PendingQuestion pending;

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
    widget.state.answerQuestion(widget.pending, answers);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.quiz_outlined, color: Color(0xFF8FA6FF)),
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
            child: Text(header,
                style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.6,
                    color: Color(0xFF8FA6FF))),
          ),
        Text(question,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
        if (detail != null && detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(detail,
                style: const TextStyle(
                    fontSize: 12.5, color: Colors.white54, height: 1.45)),
          ),
        if (multi)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('可多选',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ),
        const SizedBox(height: 10),
        for (final option in options)
          _optionTile(id, option, multi,
              selected.contains(option['label'] as String? ?? '')),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextField(
            controller: _customFor(id),
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: options.isEmpty ? '输入回答' : '其他(可选)',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.white30),
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
      String id, Map<String, dynamic> option, bool multi, bool selected) {
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
            color: selected
                ? primary.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? primary.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.12),
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
                color: selected ? primary : Colors.white38,
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
                        child: Text(description,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white38)),
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

class Composer extends StatefulWidget {
  const Composer({super.key, required this.state});

  final AppState state;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.state.sendPrompt(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.state.selectedSessionId != null;
    final canSend = enabled && _controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.only(left: 18, right: 6, top: 5, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 15.5),
                  decoration: InputDecoration(
                    hintText: enabled ? '发消息给 DSH…' : '先选择或新建一个会话',
                    hintStyle: const TextStyle(color: Colors.white30),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (widget.state.selectedRunning)
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.red.withValues(alpha: 0.5)),
                    ),
                    child: IconButton(
                      tooltip: '停止生成',
                      icon: const Icon(Icons.stop_rounded,
                          color: Colors.redAccent),
                      onPressed: () => widget.state.cancelTurn(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: canSend ? kBrandGradient : null,
                    color: canSend
                        ? null
                        : Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: '发送',
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: canSend ? Colors.white : Colors.white24,
                    ),
                    onPressed: canSend ? _send : null,
                  ),
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
// Stats bar
// ---------------------------------------------------------------------------

class StatsBar extends StatelessWidget {
  const StatsBar({super.key, required this.state});

  final AppState state;

  num? _num(Map<String, dynamic>? map, String key) => map?[key] as num?;

  @override
  Widget build(BuildContext context) {
    final sessionId = state.selectedSessionId;
    if (sessionId == null) return const SizedBox.shrink();
    final stats = state.projectionOf(sessionId, 'sessionStats');
    final usage = state.projectionOf(sessionId, 'tokenUsage');
    final pressure = state.projectionOf(sessionId, 'contextPressure');
    if (stats == null && usage == null) return const SizedBox.shrink();

    final chips = <Widget>[];
    final turns = _num(stats, 'turns');
    final steps = _num(stats, 'steps');
    if (turns != null && steps != null) {
      chips.add(_StatChip(icon: Icons.loop, label: '$turns 轮 · $steps 步'));
    }
    final llmMs = _num(stats, 'llmMs');
    final toolMs = _num(stats, 'toolMs');
    if (llmMs != null) {
      chips.add(_StatChip(
        icon: Icons.schedule,
        label: 'LLM ${_fmtDuration(llmMs)} · 工具 ${_fmtDuration(toolMs ?? 0)}',
      ));
    }
    final ttftMs = _num(stats, 'ttftMs');
    final ttftSteps = _num(stats, 'ttftSteps');
    if (ttftMs != null && ttftSteps != null && ttftSteps > 0) {
      chips.add(_StatChip(
          icon: Icons.bolt,
          label: '首 token 平均 ${_fmtDuration(ttftMs / ttftSteps)}'));
    }
    final decodeMs = _num(stats, 'decodeMs');
    final decodeTokens = _num(stats, 'decodeTokens');
    if (decodeMs != null && decodeMs > 0 && decodeTokens != null) {
      final speed = decodeTokens / (decodeMs / 1000);
      chips.add(_StatChip(
          icon: Icons.speed, label: '${speed.toStringAsFixed(0)} tok/s'));
    }
    final uncached = _num(usage, 'uncachedInputTokens');
    final output = _num(usage, 'outputTokens');
    final cacheRead = _num(usage, 'cacheReadTokens');
    if (cacheRead != null && uncached != null && cacheRead + uncached > 0) {
      final pct = cacheRead / (cacheRead + uncached) * 100;
      chips.add(_StatChip(
          icon: Icons.cached, label: '缓存命中 ${pct.toStringAsFixed(0)}%'));
    }
    if (uncached != null || output != null) {
      chips.add(_StatChip(
        icon: Icons.swap_vert,
        label: '输入 ${_fmtTokens(uncached ?? 0)} · 输出 ${_fmtTokens(output ?? 0)}',
      ));
    }
    final projected =
        _num(pressure, 'projectedTokens') ?? _num(pressure, 'pressureTokens');
    final window = _num(pressure, 'contextWindow');
    if (projected != null && window != null && window > 0) {
      chips.add(_ContextChip(used: projected, total: window));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => chips[index],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF8FA6FF)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
        ],
      ),
    );
  }
}

/// Context-window usage chip with inline progress bar.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.used, required this.total});

  final num used;
  final num total;

  @override
  Widget build(BuildContext context) {
    final ratio = (used / total).clamp(0.0, 1.0);
    final pct = ratio * 100;
    final color = pct >= 85
        ? Colors.redAccent
        : pct >= 70
            ? Colors.amber
            : Colors.greenAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.data_usage, size: 13, color: color),
          const SizedBox(width: 5),
          Text('上下文 ${pct.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11.5, color: color)),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDuration(num ms) {
  if (ms < 1000) return '${ms.round()}ms';
  final seconds = ms / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).round();
  return '${minutes}m${rest}s';
}

String _fmtTokens(num tokens) {
  if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M tok';
  if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K tok';
  return '$tokens tok';
}

// ---------------------------------------------------------------------------
// Model picker
// ---------------------------------------------------------------------------

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({super.key, required this.state});

  final AppState state;

  bool _isCurrent(String provider, String model) {
    final current = state.models?.current ?? const {};
    return current['provider'] == provider && current['model'] == model;
  }

  Future<void> _pick(BuildContext context, String provider,
      Map<String, dynamic> model) async {
    final modelId = model['id'] as String? ?? '';
    if (modelId.isEmpty) return;
    final reasoning = (model['reasoning'] as Map?)?.cast<String, dynamic>();
    final efforts = ((reasoning?['efforts'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    String? effort;
    if (efforts.isNotEmpty) {
      effort = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('推理强度'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('默认'),
            ),
            for (final e in efforts)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(e['id'] as String? ?? ''),
                child: Text(e['name'] as String? ?? e['id'] as String? ?? ''),
              ),
          ],
        ),
      );
      // Dismissed without a choice: leave the selection untouched.
      if (effort == null) return;
    }
    if (!context.mounted) return;
    final name = model['name'] as String? ?? modelId;
    final chosenEffort = (effort == null || effort.isEmpty) ? null : effort;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.selectModel(provider, modelId,
          reasoningEffort: chosenEffort);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(chosenEffort == null
            ? '已切换模型: $name'
            : '已切换模型: $name · 推理强度 $chosenEffort'),
        duration: const Duration(seconds: 2),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text('切换失败: $error'),
        backgroundColor: Colors.red.shade900,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = state.models;
    if (models == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('模型目录不可用')),
      );
    }
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('选择模型',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (models.current['model'] != null)
                      Text(
                        '当前: ${models.label}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white38),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final group in models.groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      (group['name'] as String? ?? group['id'] as String? ?? '')
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 1.1,
                          color: Color(0xFF8FA6FF),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final model
                      in ((group['models'] as List?) ?? const [])
                          .map((m) => (m as Map).cast<String, dynamic>()))
                    _modelTile(context, group['id'] as String? ?? '', model),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modelTile(
      BuildContext context, String provider, Map<String, dynamic> model) {
    final id = model['id'] as String? ?? '';
    final name = model['name'] as String? ?? id;
    final description = model['description'] as String?;
    final current = _isCurrent(provider, id);
    final reasoning = (model['reasoning'] as Map?)?.cast<String, dynamic>();
    final hasEfforts =
        ((reasoning?['efforts'] as List?) ?? const []).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: current
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(name,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: current ? FontWeight.w600 : FontWeight.normal)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(id,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: Colors.white38)),
              if (description != null && description.isNotEmpty)
                Text(description,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white38)),
              if (current &&
                  (state.models?.current['reasoningEffort'] as String? ?? '')
                      .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _MiniChip(
                    icon: Icons.tune,
                    label:
                        '推理强度 ${state.models!.current['reasoningEffort']}',
                    color: const Color(0xFF8FA6FF),
                  ),
                ),
            ],
          ),
          trailing: current
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : hasEfforts
                  ? const Icon(Icons.tune, size: 18, color: Colors.white38)
                  : null,
          onTap: () => _pick(context, provider, model),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Changelog
// ---------------------------------------------------------------------------

/// Display metadata of one changelog change type.
({Color color, IconData icon, String label}) _changeTypeMeta(
        ChangelogChangeType type) =>
    switch (type) {
      ChangelogChangeType.feature => (
          color: Colors.greenAccent,
          icon: Icons.auto_awesome,
          label: '新功能',
        ),
      ChangelogChangeType.improvement => (
          color: const Color(0xFF8FA6FF),
          icon: Icons.trending_up,
          label: '优化',
        ),
      ChangelogChangeType.fix => (
          color: Colors.orangeAccent,
          icon: Icons.bug_report_outlined,
          label: '修复',
        ),
    };

/// One change row: colored type chip plus the change text.
class _ChangelogChangeRow extends StatelessWidget {
  const _ChangelogChangeRow({required this.change});

  final ChangelogChange change;

  @override
  Widget build(BuildContext context) {
    final meta = _changeTypeMeta(change.type);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: meta.color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(meta.icon, size: 11, color: meta.color),
                const SizedBox(width: 3),
                Text(meta.label,
                    style: TextStyle(fontSize: 10, color: meta.color)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(change.text,
                style: const TextStyle(
                    fontSize: 13, height: 1.45, color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

/// Full release-notes page, reachable from the drawer.
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final release in kChangelog)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('v${release.version}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (release.version == kLatestRelease.version) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: kBrandGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('当前',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ),
                      ],
                      const Spacer(),
                      Text(release.date,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white38)),
                    ],
                  ),
                  const Divider(height: 18),
                  for (final change in release.changes)
                    _ChangelogChangeRow(change: change),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Post-update dialog summarizing the latest release.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final release = kLatestRelease;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.new_releases_outlined, color: Color(0xFF8FA6FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('v${release.version} 更新内容',
                style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in release.changes)
                _ChangelogChangeRow(change: change),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChangelogPage()),
            );
          },
          child: const Text('查看全部'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// New-session directory picker
// ---------------------------------------------------------------------------

/// New-session sheet: create in the default workspace (checked by default),
/// or uncheck to pick a registered workspace / enter a custom directory.
class NewSessionSheet extends StatefulWidget {
  const NewSessionSheet({super.key, required this.state});

  final AppState state;

  @override
  State<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<NewSessionSheet> {
  bool _useDefault = true;
  String? _selectedWorkspaceId;
  bool _customMode = false;
  final TextEditingController _customPath = TextEditingController();
  bool _creating = false;
  String? _error;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.loadWorkspaces();
    _customPath.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _customPath.dispose();
    super.dispose();
  }

  bool get _canCreate {
    if (_creating) return false;
    if (_useDefault) return true;
    if (_customMode) return _customPath.text.trim().isNotEmpty;
    return _selectedWorkspaceId != null;
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      if (_useDefault) {
        await state.createSession();
      } else if (_customMode) {
        await state.createSession(cwd: _customPath.text.trim());
      } else {
        await state.createSession(workspaceId: _selectedWorkspaceId);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.add_comment_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('新建会话',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _defaultTile(),
                  if (!_useDefault) ...[
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 6),
                      child: Text('选择工作区目录',
                          style: TextStyle(
                              fontSize: 11.5,
                              letterSpacing: 0.6,
                              color: Color(0xFF8FA6FF))),
                    ),
                    if (state.loadingWorkspaces)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      for (final workspace in state.workspaces)
                        _workspaceTile(workspace),
                      _customTile(),
                      if (state.workspaces.isEmpty && !_customMode)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('没有已注册的工作区,可使用自定义路径',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white38)),
                        ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text('创建失败: $_error',
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 16),
                  _GradientButton(
                    label: '创建',
                    loading: _creating,
                    onPressed: _canCreate ? _create : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _useDefault = !_useDefault),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _useDefault
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _useDefault
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _useDefault ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: _useDefault
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white38,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('在默认工作区创建', style: TextStyle(fontSize: 14)),
                  Text('使用服务器的默认目录',
                      style: TextStyle(fontSize: 11.5, color: Colors.white38)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceTile(Map<String, dynamic> workspace) {
    final id = workspace['workspaceId'] as String? ?? '';
    final title = workspace['title'] as String? ?? '';
    final path = workspace['path'] as String? ?? '';
    final sessions = (workspace['sessionIds'] as List?)?.length ?? 0;
    final selected = !_customMode && _selectedWorkspaceId == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _customMode = false;
          _selectedWorkspaceId = id;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    Text(path,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.white38)),
                  ],
                ),
              ),
              Text('$sessions 个会话',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white30)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _customMode = true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _customMode
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _customMode
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _customMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: _customMode
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white38,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('自定义路径', style: TextStyle(fontSize: 14)),
                ),
                const Icon(Icons.edit_outlined,
                    size: 16, color: Colors.white38),
              ],
            ),
          ),
        ),
        if (_customMode)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _customPath,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: '/home/you/project',
                hintStyle: const TextStyle(color: Colors.white30),
                helperText: '必须是服务器上已存在的目录',
                helperStyle:
                    const TextStyle(fontSize: 11, color: Colors.white38),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _fmtBytes(int bytes) {
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

// ---------------------------------------------------------------------------
// Update download
// ---------------------------------------------------------------------------

/// Modal download-progress dialog; on completion it hands the APK to the
/// system installer and closes itself.
class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.checker, required this.info});

  final UpdateChecker checker;
  final UpdateInfo info;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  int _received = 0;
  int? _total;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final file = await widget.checker.downloadApk(
        widget.info,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.checker.install(file);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final progress = total != null && total > 0 ? _received / total : null;
    return AlertDialog(
      title: Text('下载 v${widget.info.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(_error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13))
          else ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 10),
            Text(
              total != null
                  ? '${_fmtBytes(_received)} / ${_fmtBytes(total)}'
                  : '${_fmtBytes(_received)} 已下载',
              style: const TextStyle(fontSize: 12.5, color: Colors.white54),
            ),
            if (progress != null)
              Text('${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12.5, color: Colors.white54)),
          ],
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
      ],
    );
  }
}

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
import 'src/notifications.dart';
import 'src/protocol.dart';
import 'src/social.dart';
import 'src/theme.dart';
import 'src/updater.dart';
import 'chat_view.dart';
import 'session_drawer.dart';
import 'composer.dart';
import 'task_queue.dart';
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
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: P.accent.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'assets/branding/hermes-agent-icon-512.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            decoration: BoxDecoration(gradient: P.brandGradient),
            child: Icon(
              Icons.auto_awesome,
              color: P.onAccent,
              size: size * 0.5,
            ),
          ),
        ),
      ),
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
  final _lanUrl = TextEditingController();
  String _connectionMode = 'public';

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('authUser');
    if (!mounted) return;
    setState(() {
      if (user != null) _user.text = user;
      _connectionMode = prefs.getString('connectionMode') ?? 'public';
      _lanUrl.text =
          prefs.getString('lanServerUrl') ?? 'http://192.168.1.100:3080';
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _lanUrl.dispose();
    super.dispose();
  }

  String? _preError;

  Future<void> _connect() async {
    final user = _user.text.trim();
    final pass = _pass.text;
    if (user.isEmpty || pass.isEmpty) return;
    setState(() => _preError = null);
    var serverUrl = kDefaultServerUrl;
    if (_connectionMode == 'lan') {
      serverUrl = _normalizeServerUrl(_lanUrl.text);
      if (serverUrl.isEmpty) {
        setState(() => _preError = '请输入电脑的本地网络地址');
        return;
      }
    } else {
      // Public login resolves the account's instance through the central directory.
      try {
        serverUrl = await directoryLogin(kDefaultServerUrl, user, pass);
      } on DshError catch (error) {
        if (error.code == 'directory-auth') {
          setState(() => _preError = '用户名或密码错误');
          return;
        }
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authUser', user);
    await prefs.setString('authPass', pass);
    await prefs.setString('connectionMode', _connectionMode);
    if (_connectionMode == 'lan') {
      await prefs.setString('lanServerUrl', serverUrl);
    } else {
      await prefs.setString('remoteServerUrl', serverUrl);
    }
    await prefs.setString('serverUrl', serverUrl);
    await widget.state.connect(serverUrl, username: user, password: pass);
  }

  String _normalizeServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return '';
    return uri
        .replace(path: '', query: null, fragment: null)
        .toString()
        .replaceAll(RegExp(r'/$'), '');
  }

  String _friendlyConnectionError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return '账号或密码没有通过验证，请检查后重试。';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return _connectionMode == 'lan'
          ? '连接超时。请确认手机和电脑在同一 Wi-Fi，并检查电脑地址和防火墙。'
          : '连接超时。请确认电脑在线，并检查公网服务或隧道是否正常。';
    }
    if (lower.contains('socket') || lower.contains('connection refused')) {
      return _connectionMode == 'lan'
          ? '没有找到电脑服务。请先在电脑启动 DSH，再检查 IP 地址和 3080 端口。'
          : '暂时无法连接你的电脑。请确认电脑已开机并保持 DSH 在线。';
    }
    return '暂时无法连接，请检查电脑是否在线或打开配置教程自查。';
  }

  void _showConnectionGuide([String? initialMode]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          ConnectionGuideSheet(initialMode: initialMode ?? _connectionMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(kDefaultServerUrl).host;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: P.isDark
                ? [
                    P.bg,
                    Color.lerp(P.bg, P.accent, 0.12)!,
                    Color.lerp(P.bg, P.accent2, 0.16)!,
                  ]
                : [
                    P.bg,
                    Color.lerp(P.bg, P.accent, 0.06)!,
                    Color.lerp(P.bg, P.accent2, 0.09)!,
                  ],
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
                    final error = _preError ?? widget.state.connectionError;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _BrandMark(size: 84),
                        const SizedBox(height: 20),
                        Text(
                          'xHarness',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '用手机安全连接并操作你自己的电脑',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: P.textSecondary),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: P.card,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: P.isDark ? P.fillLight : P.divider,
                            ),
                            boxShadow: P.cardShadow,
                          ),
                          child: Column(
                            children: [
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'public',
                                    icon: Icon(Icons.public),
                                    label: Text('远程连接'),
                                  ),
                                  ButtonSegment(
                                    value: 'lan',
                                    icon: Icon(Icons.wifi),
                                    label: Text('本地连接'),
                                  ),
                                ],
                                selected: {_connectionMode},
                                onSelectionChanged: (selection) => setState(() {
                                  _connectionMode = selection.first;
                                  _preError = null;
                                }),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: P.fillLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _connectionMode == 'lan'
                                          ? Icons.speed
                                          : Icons.cloud_outlined,
                                      size: 18,
                                      color: P.accentLight,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _connectionMode == 'lan'
                                            ? '适合在家使用：手机和电脑同一 Wi-Fi，速度快，但离开家后不可用'
                                            : '适合外出使用：由官网找到你的电脑，安全要求更高，电脑需要保持在线',
                                        style: TextStyle(
                                          color: P.textSecondary,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _showConnectionGuide(),
                                      child: const Text('怎么配置？'),
                                    ),
                                  ],
                                ),
                              ),
                              if (_connectionMode == 'lan') ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: P.danger.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: P.danger.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 18,
                                        color: P.danger,
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          '当前本地连接适合可信家庭网络。不要在酒店、商场或公共 Wi-Fi 使用，也不要把电脑端口直接开放到互联网。',
                                          style: TextStyle(
                                            fontSize: 12.2,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _lanUrl,
                                  keyboardType: TextInputType.url,
                                  decoration: _loginDecoration(
                                    '电脑地址，例如 192.168.1.100:3080',
                                    Icons.lan_outlined,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextField(
                                controller: _user,
                                autofillHints: const [AutofillHints.username],
                                decoration: _loginDecoration(
                                  '用户名',
                                  Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pass,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _connect(),
                                decoration: _loginDecoration(
                                  '密码',
                                  Icons.lock_outline,
                                ),
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: P.danger.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: P.danger.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: P.danger,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _preError != null
                                              ? _preError!
                                              : _friendlyConnectionError(error),
                                          style: TextStyle(
                                            color: P.danger,
                                            fontSize: 12.5,
                                          ),
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
                                onPressed: widget.state.connecting
                                    ? null
                                    : _connect,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 13,
                              color: P.textTertiary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$host · 自动匹配你的实例',
                              style: TextStyle(
                                color: P.textTertiary,
                                fontSize: 12,
                              ),
                            ),
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
      fillColor: P.fillSubtle,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: P.fillLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: P.fillLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: P.accent, width: 1.5),
      ),
    );
  }
}

/// Full-width gradient action button with loading state.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    this.onPressed,
    this.loading = false,
  });

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
          gradient: enabled ? P.brandGradient : null,
          color: enabled ? null : P.fillLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: P.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: P.onAccent,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

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

class ConnectionGuideSheet extends StatefulWidget {
  const ConnectionGuideSheet({super.key, this.initialMode = 'public'});

  final String initialMode;

  @override
  State<ConnectionGuideSheet> createState() => _ConnectionGuideSheetState();
}

class _ConnectionGuideSheetState extends State<ConnectionGuideSheet> {
  late String _mode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mode == 'public' ? '远程连接：让官网帮你找到电脑' : '本地连接：手机直连电脑',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '先看适合谁、需要准备什么，再按步骤完成。高级命令可直接点按复制。',
                style: TextStyle(color: P.textSecondary),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'public',
                    icon: Icon(Icons.public),
                    label: Text('远程连接'),
                  ),
                  ButtonSegment(
                    value: 'lan',
                    icon: Icon(Icons.wifi),
                    label: Text('本地连接'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
              const SizedBox(height: 18),
              if (_mode == 'public') ...[
                const _GuideStep(
                  number: 1,
                  title: '准备一台保持在线的电脑',
                  detail: '这台电脑就是你的 AI 工作电脑，需要安装并运行 DSH。',
                  code: 'dsh web --no-open',
                ),
                const _GuideStep(
                  number: 2,
                  title: '申请远程连接服务',
                  detail:
                      '目前需要管理员为你的电脑配置安全域名、HTTPS、登录保护和网络隧道。普通用户不需要自己开放路由器端口。',
                ),
                const _GuideStep(
                  number: 3,
                  title: '使用官网账号登录',
                  detail: '管理员绑定完成后，你只需要输入账号和密码，App 会自动找到你的电脑。',
                ),
                const _GuideTip(
                  text: '安全说明：远程连接必须使用 HTTPS 和身份认证。配对码与设备密钥方案仍在规划中，当前不会声称已经支持。',
                ),
              ] else ...[
                const _GuideStep(
                  number: 1,
                  title: '让手机和电脑连接同一可信网络',
                  detail: '访客网络或开启 AP 隔离的 Wi-Fi 可能无法互相访问。',
                ),
                const _GuideStep(
                  number: 2,
                  title: '让电脑只在家里可见',
                  detail: '在可信家庭网络中启动局域网服务，并保持窗口开启。不要把这个端口转发到公网。',
                  code: 'dsh web --host 0.0.0.0 --port 3080 --no-open',
                ),
                const _GuideStep(
                  number: 3,
                  title: '查找电脑局域网 IP',
                  detail:
                      'Linux/macOS 可运行 hostname -I 或在网络设置查看，例如 192.168.1.100。',
                  code: 'hostname -I',
                ),
                const _GuideStep(
                  number: 4,
                  title: '在 App 填写电脑地址',
                  detail: '填写 http://电脑IP:3080。当前直连模式的账号保护取决于电脑前是否配置认证代理。',
                ),
                const _GuideTip(
                  text:
                      '安全说明：只在可信家庭网络使用。离开 Wi-Fi 后不可用；不要在公共网络使用，也不要把 3080 端口开放到互联网。',
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('我知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.detail,
    this.code,
  });

  final int number;
  final String title;
  final String detail;
  final String? code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: P.accent,
            foregroundColor: P.onAccent,
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(color: P.textSecondary, height: 1.4),
                ),
                if (code != null) ...[
                  const SizedBox(height: 7),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code!));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('命令已复制')));
                    },
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: P.fillLight,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              code!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Icon(Icons.copy, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideTip extends StatelessWidget {
  const _GuideTip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: P.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: P.accent.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(Icons.tips_and_updates_outlined, color: P.accentLight),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: P.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
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
      builder: (_) => _UpdateDownloadDialog(checker: checker, info: info),
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
      builder: (dialogContext) => _UpdateAvailableDialog(
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
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: P.textTertiary),
                  ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Divider(height: 0.5, color: P.divider),
            ),
            actions: [
              if (sessionId != null && state.subagents.isNotEmpty)
                _SubagentStatusButton(state: state),
              if (sessionId != null && state.hasQueuedTasks)
                TaskQueueButton(state: state),
              if (sessionId != null)
                IconButton(
                  tooltip: '切换模型',
                  onPressed: state.loadingModels ? null : _showModelPicker,
                  icon: const Icon(Icons.smart_toy_outlined, size: 21),
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
                    case 'update':
                      _checkForUpdate(manual: true);
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
                  if (defaultTargetPlatform == TargetPlatform.android)
                    const PopupMenuItem(
                      value: 'update',
                      child: ListTile(
                        leading: Icon(Icons.system_update_alt_outlined),
                        title: Text('检查更新'),
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
            const _BrandMark(size: 76),
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

class _SubagentStatusButton extends StatelessWidget {
  const _SubagentStatusButton({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final running = state.subagents.where((entry) => entry.running).length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: running > 0 ? '$running 个子代理正在工作' : '查看子代理',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => _SubagentSheet(state: state),
          ),
          icon: Icon(
            Icons.account_tree_outlined,
            color: running > 0 ? P.success : P.textSecondary,
          ),
        ),
        if (running > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 17,
              height: 17,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: P.success,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$running',
                style: TextStyle(
                  color: P.onAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubagentSheet extends StatelessWidget {
  const _SubagentSheet({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '子代理运行状态',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: state.loadingSubagents
                    ? null
                    : state.refreshSubagents,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final agent in state.subagents)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                agent.running
                    ? Icons.autorenew_rounded
                    : Icons.check_circle_outline,
                color: agent.running ? P.success : P.textTertiary,
              ),
              title: Text(
                agent.label?.isNotEmpty == true ? agent.label! : '子代理',
              ),
              subtitle: Text(
                '${agent.mode == 'continuable' ? '可继续' : '单次任务'}${agent.hasChildren ? ' · 包含下级代理' : ''}',
              ),
              trailing: Text(
                agent.running ? '工作中' : '已完成',
                style: TextStyle(
                  color: agent.running ? P.success : P.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    ),
  );
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
      chips.add(
        _StatChip(
          icon: Icons.schedule,
          label: 'LLM ${_fmtDuration(llmMs)} · 工具 ${_fmtDuration(toolMs ?? 0)}',
        ),
      );
    }
    final ttftMs = _num(stats, 'ttftMs');
    final ttftSteps = _num(stats, 'ttftSteps');
    if (ttftMs != null && ttftSteps != null && ttftSteps > 0) {
      chips.add(
        _StatChip(
          icon: Icons.bolt,
          label: '首 token 平均 ${_fmtDuration(ttftMs / ttftSteps)}',
        ),
      );
    }
    final decodeMs = _num(stats, 'decodeMs');
    final decodeTokens = _num(stats, 'decodeTokens');
    if (decodeMs != null && decodeMs > 0 && decodeTokens != null) {
      final speed = decodeTokens / (decodeMs / 1000);
      chips.add(
        _StatChip(
          icon: Icons.speed,
          label: '${speed.toStringAsFixed(0)} tok/s',
        ),
      );
    }
    final uncached = _num(usage, 'uncachedInputTokens');
    final output = _num(usage, 'outputTokens');
    final cacheRead = _num(usage, 'cacheReadTokens');
    if (cacheRead != null && uncached != null && cacheRead + uncached > 0) {
      final pct = cacheRead / (cacheRead + uncached) * 100;
      chips.add(
        _StatChip(icon: Icons.cached, label: '缓存命中 ${pct.toStringAsFixed(0)}%'),
      );
    }
    if (uncached != null || output != null) {
      chips.add(
        _StatChip(
          icon: Icons.swap_vert,
          label:
              '输入 ${_fmtTokens(uncached ?? 0)} · 输出 ${_fmtTokens(output ?? 0)}',
        ),
      );
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
        border: Border(bottom: BorderSide(color: P.fillLight)),
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
        color: P.fillSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: P.fillMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: P.accentLight),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11.5, color: P.textSecondary)),
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
        ? P.danger
        : pct >= 70
        ? Colors.amber
        : P.success;
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
          Text(
            '上下文 ${pct.toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11.5, color: color),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 5,
                backgroundColor: P.fillLight,
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

  Future<void> _pick(
    BuildContext context,
    String provider,
    Map<String, dynamic> model,
  ) async {
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
      await state.selectModel(provider, modelId, reasoningEffort: chosenEffort);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            chosenEffort == null
                ? '已切换模型: $name'
                : '已切换模型: $name · 推理强度 $chosenEffort',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('切换失败: $error'),
          backgroundColor: P.danger,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = state.models;
    if (models == null) {
      return const SizedBox(height: 200, child: Center(child: Text('模型目录不可用')));
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
                    Text(
                      '选择模型',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (models.current['model'] != null)
                      Text(
                        '当前: ${models.label}',
                        style: TextStyle(fontSize: 12, color: P.textTertiary),
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
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                        color: P.accentLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final model
                      in ((group['models'] as List?) ?? const []).map(
                        (m) => (m as Map).cast<String, dynamic>(),
                      ))
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
    BuildContext context,
    String provider,
    Map<String, dynamic> model,
  ) {
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
            : P.fillSubtle,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            name,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: current ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                id,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: P.textTertiary,
                ),
              ),
              if (description != null && description.isNotEmpty)
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: P.textTertiary),
                ),
              if (current &&
                  (state.models?.current['reasoningEffort'] as String? ?? '')
                      .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: MiniChip(
                    icon: Icons.tune,
                    label: '推理强度 ${state.models!.current['reasoningEffort']}',
                    color: P.accentLight,
                  ),
                ),
            ],
          ),
          trailing: current
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                )
              : hasEfforts
              ? Icon(Icons.tune, size: 18, color: P.textTertiary)
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
  ChangelogChangeType type,
) => switch (type) {
  ChangelogChangeType.feature => (
    color: P.success,
    icon: Icons.auto_awesome,
    label: '新功能',
  ),
  ChangelogChangeType.improvement => (
    color: P.accentLight,
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
                Text(
                  meta.label,
                  style: TextStyle(fontSize: 10, color: meta.color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              change.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: P.textSecondary,
              ),
            ),
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
                color: P.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: P.fillLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'v${release.version}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (release.version == kLatestRelease.version) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: P.brandGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '当前',
                            style: TextStyle(fontSize: 10, color: P.onAccent),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        release.date,
                        style: TextStyle(fontSize: 12, color: P.textTertiary),
                      ),
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
          Icon(Icons.new_releases_outlined, color: P.accentLight),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'v${release.version} 更新内容',
              style: const TextStyle(fontSize: 17),
            ),
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
                      Text(
                        '新建会话',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _defaultTile(),
                  if (!_useDefault) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        '选择工作区目录',
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 0.6,
                          color: P.accentLight,
                        ),
                      ),
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
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            '没有已注册的工作区,可使用自定义路径',
                            style: TextStyle(
                              fontSize: 12,
                              color: P.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '创建失败: $_error',
                      style: TextStyle(fontSize: 12.5, color: P.danger),
                    ),
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
              : P.fillSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _useDefault
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                : P.fillLight,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _useDefault ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: _useDefault
                  ? Theme.of(context).colorScheme.primary
                  : P.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('在默认工作区创建', style: TextStyle(fontSize: 14)),
                  Text(
                    '使用服务器的默认目录',
                    style: TextStyle(fontSize: 11.5, color: P.textTertiary),
                  ),
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
                : P.fillSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                  : P.fillLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : P.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    Text(
                      path,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: P.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$sessions 个会话',
                style: TextStyle(fontSize: 11, color: P.textTertiary),
              ),
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
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.16)
                  : P.fillSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _customMode
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.6)
                    : P.fillLight,
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
                      : P.textTertiary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('自定义路径', style: TextStyle(fontSize: 14)),
                ),
                Icon(Icons.edit_outlined, size: 16, color: P.textTertiary),
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
                hintStyle: TextStyle(color: P.textTertiary),
                helperText: '必须是服务器上已存在的目录',
                helperStyle: TextStyle(fontSize: 11, color: P.textTertiary),
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

/// Branded update-available dialog: gradient hero, version/size chips, and a
/// scrollable release-notes card above a full-width gradient CTA.
class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({required this.info, required this.onUpdate});

  final UpdateInfo info;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: P.cardAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // gradient hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(gradient: P.brandGradient),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: P.onAccent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    size: 28,
                    color: P.onAccent,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '发现新版本',
                  style: TextStyle(
                    color: P.onAccent,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'v${info.version}',
                  style: TextStyle(
                    color: P.onAccent.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.size != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: P.fillSubtle,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.save_alt_rounded,
                          size: 13,
                          color: P.textTertiary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '安装包 ${_fmtBytes(info.size!)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: P.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (info.notes != null && info.notes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: P.fillSubtle,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        info.notes!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: P.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                // gradient CTA
                Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: P.brandGradient,
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [P.brandGlow],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(23),
                      onTap: onUpdate,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.download_rounded,
                              size: 18,
                              color: P.onAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '立即更新',
                              style: TextStyle(
                                color: P.onAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '稍后',
                      style: TextStyle(color: P.textTertiary, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

  /// Smoothed download speed (bytes/s), sampled from progress callbacks.
  double? _speed;
  int _lastSampled = 0;
  int _lastSampleTime = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _sampleSpeed(int received) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSampleTime == 0) {
      _lastSampleTime = now;
      _lastSampled = received;
      return;
    }
    final dt = now - _lastSampleTime;
    if (dt < 500) return;
    final instant = (received - _lastSampled) / (dt / 1000);
    _speed = _speed == null ? instant : _speed! * 0.6 + instant * 0.4;
    _lastSampleTime = now;
    _lastSampled = received;
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _received = 0;
      _total = null;
      _speed = null;
      _lastSampleTime = 0;
    });
    try {
      final file = await widget.checker.downloadApk(
        widget.info,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
              _sampleSpeed(received);
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
    return Dialog(
      backgroundColor: P.cardAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '正在下载更新',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              'v${widget.info.version}',
              style: TextStyle(fontSize: 12.5, color: P.textTertiary),
            ),
            const SizedBox(height: 22),
            if (_error != null) ...[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: P.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 26,
                  color: P.danger,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '下载失败',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: P.danger,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: P.textTertiary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('关闭', style: TextStyle(color: P.textTertiary)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                    style: FilledButton.styleFrom(
                      backgroundColor: P.accent,
                      foregroundColor: P.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 108,
                      height: 108,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: P.fillLight,
                        valueColor: AlwaysStoppedAnimation(P.accent),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          progress != null
                              ? '${(progress * 100).toStringAsFixed(0)}%'
                              : '…',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: P.text,
                          ),
                        ),
                        if (_speed != null)
                          Text(
                            '${_fmtBytes(_speed!.round())}/s',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: P.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                total != null
                    ? '${_fmtBytes(_received)} / ${_fmtBytes(total)}'
                    : '已下载 ${_fmtBytes(_received)}',
                style: TextStyle(fontSize: 12, color: P.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                '完成后将自动打开安装界面',
                style: TextStyle(fontSize: 11, color: P.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slash commands
// ---------------------------------------------------------------------------

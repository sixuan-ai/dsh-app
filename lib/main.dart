/// xHarness — Flutter client for the DeepSeek Harness web API.
///
/// Server URL is a built-in default; the user only ever enters credentials.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/ai_hub_pages.dart';
import 'src/changelog.dart';
import 'src/notifications.dart';
import 'src/protocol.dart';
import 'src/social.dart';
import 'src/theme.dart';
import 'src/updater.dart';
import 'pet_page.dart';
import 'social_page.dart';
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
// Session drawer
// ---------------------------------------------------------------------------

class SessionDrawer extends StatefulWidget {
  const SessionDrawer({
    super.key,
    required this.state,
    required this.theme,
    required this.onLogout,
    required this.onNewSession,
    required this.onCheckUpdate,
    required this.onConnectionCenter,
    required this.connectionMode,
    required this.localAvailable,
    required this.updateAvailable,
  });

  final AppState state;
  final ThemeController theme;
  final VoidCallback onLogout;

  /// Opens the new-session directory picker (HomePage owns the context).
  final VoidCallback onNewSession;

  /// Runs a manual update check (HomePage owns the context).
  final VoidCallback onCheckUpdate;
  final VoidCallback onConnectionCenter;
  final String connectionMode;
  final bool localAvailable;

  /// A newer release exists; shows a green dot on 检查更新.
  final bool updateAvailable;

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  /// Workspace keys (cwd) the user collapsed; persisted across launches.
  final Set<String> _collapsed = {};

  /// 0: active list, 1: running, 2: archived, 3: pinned.
  int _sessionFilter = 0;

  /// Cached social profile for the header (nickname + avatar).
  Map<String, dynamic>? _profile;
  String? _profileRaw;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('socialProfile');
    if (raw != _profileRaw && mounted) {
      _profileRaw = raw;
      setState(() {
        _profile = raw == null
            ? null
            : (jsonDecode(raw) as Map).cast<String, dynamic>();
      });
    }
  }

  void _openCommunity() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityPage(
          state: state,
          // Social backend is centralized on the main domain for all instances.
          socialBaseUrl: '$kDefaultServerUrl/social',
        ),
      ),
    );
  }

  /// Permission-mode switcher: a sheet of presets riding the host's
  /// /permission command (the same write path as the web Access chip), with
  /// a risk confirmation before danger-full-access.
  Future<void> _openPermissions() async {
    if (state.selectedSessionId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先选择或新建一个会话')));
      return;
    }
    final preset = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _PermissionSheet(
        onPick: (preset) => Navigator.of(sheetContext).pop(preset),
      ),
    );
    if (preset == null || !mounted) return;
    if (preset == 'danger-full-access') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('开启完全访问?'),
          content: const Text(
            '开启后 DSH 可读写设备上所有文件,且不再弹出审批确认。仅在信任当前任务时开启,可随时切回工作区写入。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开启'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await state.runCommand('/permission $preset');
  }

  /// The "更多功能" grid sheet. Pages (pet/changelog) close the drawer first;
  /// sub-sheets (theme/permissions) stay over the open drawer.
  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _MoreSheet(
        actions: [
          _MoreAction(
            icon: Icons.alt_route,
            label: '连接与安全',
            caption: '本地 / 远程',
            onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onConnectionCenter();
            },
          ),
          _MoreAction(
            icon: Icons.menu_book_outlined,
            label: '连接教程',
            caption: '电脑配置',
            onTap: () {
              Navigator.of(sheetContext).pop();
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const ConnectionGuideSheet(),
              );
            },
          ),
          _MoreAction(
            icon: Icons.palette_outlined,
            label: '主题',
            caption: kAppThemes
                .firstWhere(
                  (s) => s.id == widget.theme.themeId,
                  orElse: () => kAppThemes.first,
                )
                .name,
            onTap: () {
              Navigator.of(sheetContext).pop();
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => _ThemeSheet(theme: widget.theme),
              );
            },
          ),
          _MoreAction(
            icon: Icons.newspaper_outlined,
            label: 'AI 日报',
            caption: '实时聚合',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiNewsPage()),
              );
            },
          ),
          _MoreAction(
            icon: Icons.school_outlined,
            label: 'AI 知识学习',
            caption: 'Agent 教程',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiLearningPage()),
              );
            },
          ),
          _MoreAction(
            icon: Icons.pets,
            label: '宠物',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PetPage(state: state)),
              );
            },
          ),
          _MoreAction(
            icon: Icons.shield_outlined,
            label: '权限模式',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openPermissions();
            },
          ),
          // OTA 自更新仅 Android;iOS 分发必须走 App Store / TestFlight。
          if (defaultTargetPlatform == TargetPlatform.android)
            _MoreAction(
              icon: Icons.system_update_alt,
              label: '检查更新',
              dot: widget.updateAvailable,
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pop();
                widget.onCheckUpdate();
              },
            ),
          _MoreAction(
            icon: Icons.new_releases_outlined,
            label: '更新日志',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ChangelogPage()),
              );
            },
          ),
          _MoreAction(
            icon: Icons.logout,
            label: '退出登录',
            danger: true,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              widget.onLogout();
            },
          ),
        ],
      ),
    );
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
    unawaited(_loadProfile());
    final host = Uri.parse(
      state.serverUrl.isEmpty ? kDefaultServerUrl : state.serverUrl,
    ).host;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: P.brandGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileHeader(),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: P.onAccent, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'xHarness',
                        style: TextStyle(
                          color: P.onAccent,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 12,
                        color: P.onAccent.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          host,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: P.onAccent.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.sessions.length} 个会话',
                    style: TextStyle(
                      color: P.onAccent.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
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
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _filterChip(0, '会话'),
                  _filterChip(1, '运行中'),
                  _filterChip(3, '置顶'),
                  _filterChip(2, '已归档'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _groupedSessionTiles(context),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.groups_outlined, size: 20),
              title: const Text('社区', style: TextStyle(fontSize: 14)),
              onTap: _openCommunity,
            ),
            // Everything else lives in the grid sheet, so the session list
            // keeps the full remaining height no matter how many utilities
            // the app grows.
            ListTile(
              leading: const Icon(Icons.apps_rounded, size: 20),
              title: const Text('更多功能', style: TextStyle(fontSize: 14)),
              trailing:
                  widget.updateAvailable &&
                      defaultTargetPlatform == TargetPlatform.android
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: P.success,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
              onTap: _openMore,
            ),
          ],
        ),
      ),
    );
  }

  /// Social identity row at the top of the drawer header; hidden until the
  /// user joined the community once. Taps through to the community page.
  Widget _profileHeader() {
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    // Avatar URLs live on the centralized social backend (main domain).
    const base = kDefaultServerUrl;
    final userId = profile['userId'] as String? ?? '';
    final nickname = profile['nickname'] as String? ?? '';
    final ver = (profile['avatarVer'] as num?)?.toInt() ?? 0;
    final token = profile['token'] as String? ?? '';
    final headers = <String, String>{
      if ((state.authUsername ?? '').isNotEmpty)
        'authorization':
            'Basic ${base64Encode(utf8.encode('${state.authUsername}:${state.authPassword ?? ''}'))}',
      'x-social-token': token,
    };
    return InkWell(
      onTap: _openCommunity,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            if (ver > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  '$base/social/avatar?userId=$userId&v=$ver',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  headers: headers,
                  errorBuilder: (_, _, _) => _letterAvatar(nickname),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : _letterAvatar(nickname),
                ),
              )
            else
              _letterAvatar(nickname),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: P.onAccent,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Lv.${profile['level']} · ${profile['title']}',
                    style: TextStyle(
                      color: P.onAccent.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: P.onAccent.withValues(alpha: 0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _letterAvatar(String nickname) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        nickname.isEmpty ? '?' : nickname.characters.first,
        style: TextStyle(
          color: P.onAccent,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _filterChip(int value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _sessionFilter == value,
        onSelected: (_) => setState(() => _sessionFilter = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// Groups filtered sessions by workspace directory (cwd), mirroring the
  /// web client; sessions without one collect in an 未分组 section.
  List<Widget> _groupedSessionTiles(BuildContext context) {
    final filtered =
        state.sessions.where((row) {
          final archived = state.archivedSessionIds.contains(row.sessionId);
          return switch (_sessionFilter) {
            1 => !archived && row.running,
            2 => archived,
            3 => !archived && state.pinnedSessionIds.contains(row.sessionId),
            _ => !archived,
          };
        }).toList()..sort((a, b) {
          final ap = state.pinnedSessionIds.contains(a.sessionId);
          final bp = state.pinnedSessionIds.contains(b.sessionId);
          if (ap != bp) return bp ? 1 : -1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    final groups = <String, List<SessionRow>>{};
    for (final row in filtered) {
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
                color: P.accentLight,
              ),
              const SizedBox(width: 2),
              Icon(
                cwd.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
                size: 14,
                color: P.accentLight,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: cwd.isEmpty ? '未分组' : cwd,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.4,
                      color: P.accentLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: 11, color: P.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(BuildContext context, SessionRow row) {
    final selected = row.sessionId == state.selectedSessionId;
    final archived = state.archivedSessionIds.contains(row.sessionId);
    final pinned = state.pinnedSessionIds.contains(row.sessionId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          dense: true,
          leading: Icon(
            archived
                ? Icons.archive_outlined
                : pinned
                ? Icons.push_pin
                : Icons.circle,
            size: pinned || archived ? 18 : 8,
            color: archived
                ? P.textTertiary
                : pinned
                ? P.accentLight
                : row.running
                ? P.success
                : P.textTertiary,
          ),
          title: Text(
            row.title?.isNotEmpty == true ? row.title! : '新会话',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            _timeAgo(row.updatedAt),
            style: TextStyle(fontSize: 11.5, color: P.textTertiary),
          ),
          trailing: PopupMenuButton<String>(
            tooltip: '会话操作',
            onSelected: (action) => _sessionAction(row, action),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: pinned ? 'unpin' : 'pin',
                child: Text(pinned ? '取消置顶' : '置顶'),
              ),
              if (!archived)
                const PopupMenuItem(value: 'archive', child: Text('归档')),
            ],
          ),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop();
            state.openSession(row.sessionId);
          },
        ),
      ),
    );
  }

  Future<void> _sessionAction(SessionRow row, String action) async {
    if (action == 'pin' || action == 'unpin') {
      await state.setSessionPinned(row.sessionId, action == 'pin');
      return;
    }
    if (action != 'archive' || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('归档会话?'),
        content: Text(
          '归档“${row.title?.isNotEmpty == true ? row.title : '新会话'}”后,它会从默认列表隐藏,可在“已归档”中查看。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await state.archiveSession(row.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('会话已归档')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('归档失败: $error')));
      }
    }
  }
}

/// Theme picker sheet: live-preview cards for each built-in theme. Selection
/// applies instantly (the app root listens to the controller) and persists.
class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择主题',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '立即生效,自动保存',
                  style: TextStyle(color: P.textTertiary, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    for (final spec in kAppThemes)
                      _ThemeCard(
                        spec: spec,
                        selected: spec.id == theme.themeId,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          theme.select(spec.id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One theme preview card in the picker: a miniature mock of the chat page
/// rendered in that theme's own palette.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = spec.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? palette.accent : P.divider,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // mini app bar
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: palette.brandGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 42,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.text,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // mini assistant line
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: palette.divider, width: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // mini user bubble
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 56,
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: palette.brandGradient,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spec.name,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        spec.subtitle,
                        style: TextStyle(
                          color: palette.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: palette.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, size: 12, color: palette.onAccent),
                ),
              ),
          ],
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
                const Icon(Icons.military_tech, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  'Lv.${level.level} · ${level.title}',
                  style: TextStyle(
                    color: P.onAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${level.count} 次对话',
                  style: TextStyle(
                    color: P.onAccent.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: level.progress,
                minHeight: 5,
                backgroundColor: P.fillMedium,
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
                style: TextStyle(color: P.textSecondary, fontSize: 10.5),
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
                Text(
                  '每发送一条消息计 1 次对话,累计达到阈值即可升级。计数保存在本机。',
                  style: TextStyle(fontSize: 12.5, color: P.textSecondary),
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
                              : P.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lv.${i + 1} · ${levelTitles[i]}',
                            style: TextStyle(
                              fontSize: 13,
                              color: i + 1 == level.level
                                  ? Colors.amber
                                  : P.textSecondary,
                              fontWeight: i + 1 == level.level
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Text(
                          '≥ ${levelThresholds[i]} 次',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: P.textTertiary,
                          ),
                        ),
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

  /// Entrance-animation baseline: items at or above this index animate in.
  /// Initialized to the full list so history loads never animate.
  int _animBaseline = 0;
  String? _animSession;

  /// New content arrived while the user was reading above the fold.
  bool _hasNewBelow = false;
  bool _wasNearBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

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

  void _onScroll() {
    final near = _nearBottom;
    if (near == _wasNearBottom) return;
    _wasNearBottom = near;
    if (near) _hasNewBelow = false;
    setState(() {});
  }

  void _maybeScroll() {
    final count = widget.state.items.length;
    final changed = count != _lastCount;
    final streaming = widget.state.selectedStreaming;
    if (changed || streaming) {
      if (_nearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_controller.hasClients) {
            _controller.jumpTo(_controller.position.maxScrollExtent);
          }
        });
      } else if (changed && count > _lastCount) {
        // Appended while reading history: keep position, flag the jump button.
        _hasNewBelow = true;
      }
    }
    _lastCount = count;
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _hasNewBelow = false;
    _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    _maybeScroll();
    if (state.selectedSessionId != _animSession) {
      _animSession = state.selectedSessionId;
      _animBaseline = state.items.length;
    }
    if (state.items.isEmpty) {
      if (state.loadingHistory) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text('发送消息开始对话', style: TextStyle(color: P.textTertiary)),
      );
    }
    final animateFrom = _animBaseline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animBaseline = state.items.length;
    });
    final extra = state.hasMoreHistory ? 1 : 0;
    final listView = ListView.builder(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.items.length + extra,
      itemBuilder: (context, index) {
        if (index < extra) {
          return Center(
            child: TextButton.icon(
              onPressed: state.loadingHistory
                  ? null
                  : () => state.loadHistory(
                      state.selectedSessionId!,
                      older: true,
                    ),
              icon: state.loadingHistory
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: const Text('加载更早的消息'),
            ),
          );
        }
        final itemIndex = index - extra;
        final item = state.items[itemIndex];
        final prev = itemIndex > 0 ? state.items[itemIndex - 1] : null;
        final showTime = _needsTimeDivider(prev, item);
        final body = ChatItemView(
          key: ValueKey(item.id),
          state: state,
          item: item,
          animate: itemIndex >= animateFrom,
        );
        if (!showTime) return body;
        return Column(
          children: [
            _TimeDivider(time: item.time!),
            body,
          ],
        );
      },
    );
    return Stack(
      children: [
        Scrollbar(
          controller: _controller,
          interactive: true,
          thickness: 3,
          radius: const Radius.circular(2),
          child: state.hasMoreHistory
              ? RefreshIndicator(
                  color: P.accent,
                  backgroundColor: P.cardAlt,
                  onRefresh: () =>
                      state.loadHistory(state.selectedSessionId!, older: true),
                  child: listView,
                )
              : listView,
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: _ScrollToBottomButton(
            visible: !_wasNearBottom,
            hasNew: _hasNewBelow,
            onTap: _scrollToBottom,
          ),
        ),
      ],
    );
  }
}

/// QQ-style rule: a divider appears above an item when it is the first
/// timestamped item or follows a gap of more than five minutes.
bool _needsTimeDivider(ChatItem? prev, ChatItem current) {
  final time = current.time;
  if (time == null) return false;
  final prevTime = prev?.time;
  if (prevTime == null) return true;
  return time - prevTime > 5 * 60 * 1000;
}

String _fmtDividerTime(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays <= 0) return hm;
  if (diffDays == 1) return '昨天 $hm';
  if (t.year == now.year) return '${t.month}月${t.day}日 $hm';
  return '${t.year}年${t.month}月${t.day}日 $hm';
}

/// Small centered timestamp row between messages.
class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.time});

  final int time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Text(
          _fmtDividerTime(time),
          style: TextStyle(fontSize: 11, color: P.textTertiary),
        ),
      ),
    );
  }
}

/// Floating jump-to-latest button with a new-content accent dot.
class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({
    required this.visible,
    required this.hasNew,
    required this.onTap,
  });

  final bool visible;
  final bool hasNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: P.cardAlt,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: P.accentLight,
                  ),
                ),
              ),
            ),
            if (hasNew)
              Positioned(
                top: -1,
                right: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: P.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: P.cardAlt, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatItemView extends StatelessWidget {
  const ChatItemView({
    super.key,
    required this.state,
    required this.item,
    this.animate = false,
  });

  final AppState state;
  final ChatItem item;

  /// Fresh arrivals play a short fade-and-rise entrance; history restores
  /// and page prepends render statically.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (item.kind) {
      ChatItemKind.user => _UserBubble(state: state, item: item),
      ChatItemKind.assistant => _AssistantMessage(state: state, item: item),
      ChatItemKind.tool =>
        item.images.isEmpty
            ? ToolCard(state: state, item: item)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ToolImageResult(state: state, item: item),
                  ToolCard(state: state, item: item),
                ],
              ),
      ChatItemKind.notice => _NoticeCard(state: state, item: item),
    };
    if (!animate) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: body,
    );
  }
}

/// Right-aligned gradient user bubble; long-press pops the copy action.
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: GestureDetector(
          onLongPressStart: (details) =>
              _showCopyMenu(context, details.globalPosition, item.text),
          child: Container(
            margin: const EdgeInsets.only(
              left: 56,
              right: 12,
              top: 5,
              bottom: 5,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              gradient: P.brandGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
              boxShadow: [
                BoxShadow(
                  color: P.accent.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Opacity(
              opacity: item.provisional ? 0.65 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.images.isNotEmpty)
                    _ImageStrip(state: state, images: item.images),
                  if (item.text.isNotEmpty)
                    Text(
                      item.text,
                      style: TextStyle(
                        color: P.onAccent,
                        fontSize: 15.5,
                        height: 1.45,
                        fontFamily: item.text.startsWith('/')
                            ? 'monospace'
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// QQ-style long-press popup offering a single copy action.
void _showCopyMenu(BuildContext context, Offset position, String text) {
  HapticFeedback.selectionClick();
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: 'copy',
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 16, color: P.textSecondary),
            const SizedBox(width: 8),
            const Text('复制'),
          ],
        ),
      ),
    ],
  ).then((value) {
    if (value != 'copy' || !context.mounted) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  });
}

/// Full-width assistant message with avatar and markdown body.
class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  bool get _streaming => item.id.startsWith('stream-');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (item.images.isNotEmpty) {
      children.add(_ImageStrip(state: state, images: item.images));
      children.add(const SizedBox(height: 8));
    }
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
      children.add(
        const Padding(padding: EdgeInsets.only(top: 6), child: _TypingDots()),
      );
    }
    if (item.interrupted) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: _MiniChip(
            icon: Icons.stop_circle_outlined,
            label: '已中断',
            color: Colors.orange,
          ),
        ),
      );
    }
    final copyable = item.blocks
        .where((b) => b.type == 'text' && b.text.trim().isNotEmpty)
        .map((b) => b.text)
        .join('\n\n');
    if (!_streaming && copyable.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyable));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制回复内容'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.copy_rounded, size: 14, color: P.textTertiary),
            ),
          ),
        ),
      );
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
              gradient: P.brandGradient,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.auto_awesome, color: P.onAccent, size: 16),
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
    a: base.copyWith(color: P.accentLight),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      color: P.accentLight,
      backgroundColor: P.code,
    ),
    codeblockDecoration: BoxDecoration(
      color: P.code,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: P.fillLight),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: base.copyWith(color: P.textSecondary),
    blockquoteDecoration: BoxDecoration(
      color: P.fillSubtle,
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: P.accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    tableBorder: TableBorder.all(color: P.textTertiary, width: 0.5),
    tableHead: base.copyWith(fontWeight: FontWeight.bold),
    tableBody: base.copyWith(fontSize: 14),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: P.fillMedium)),
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
            final phase =
                _controller.value * 2 * math.pi + i * (2 * math.pi / 3);
            final opacity = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(phase));
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: opacity),
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
                  const Icon(
                    Icons.psychology_alt_outlined,
                    size: 16,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.streaming ? '正在思考…' : '思考过程',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.amber,
                      fontWeight: FontWeight.w500,
                    ),
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
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: P.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small label chip used for message metadata.
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

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

class _ToolImageResult extends StatelessWidget {
  const _ToolImageResult({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 16, color: P.accentLight),
              const SizedBox(width: 6),
              Text(
                '图片结果',
                style: TextStyle(
                  color: P.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '来自 ${item.name}',
                style: TextStyle(color: P.textTertiary, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ImageStrip(state: state, images: item.images),
        ],
      ),
    );
  }
}

class ToolCard extends StatefulWidget {
  const ToolCard({super.key, required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _expanded = false;

  Color get _statusColor {
    if (!widget.item.completed) return Colors.amber;
    if (widget.item.resultIsError) return P.danger;
    return P.success;
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
        color: P.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.fillLight),
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
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Icon(_icon, size: 16, color: P.textSecondary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
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
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: P.textTertiary,
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
                                '参数',
                                _truncate(summarizeArguments(item.arguments)),
                              ),
                            if (item.resultText != null) ...[
                              const SizedBox(height: 10),
                              _codeSection(
                                item.resultIsError ? '错误' : '结果',
                                _truncate(item.resultText!),
                                isError: item.resultIsError,
                              ),
                            ],
                            if (!item.completed)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '等待结果…',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: P.textTertiary,
                                    ),
                                  ),
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
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1,
            color: isError ? P.danger : P.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: P.code,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isError ? P.danger.withValues(alpha: 0.35) : P.fillLight,
            ),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: isError
                  ? P.danger.withValues(alpha: 0.9)
                  : P.textSecondary,
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
  const _NoticeCard({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isError
        ? P.danger
        : item.pending
        ? P.accentLight
        : P.textTertiary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: item.isError
            ? P.danger.withValues(alpha: 0.08)
            : item.pending
            ? P.accent.withValues(alpha: 0.08)
            : P.fillSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isError
              ? P.danger.withValues(alpha: 0.3)
              : item.pending
              ? P.accent.withValues(alpha: 0.3)
              : P.fillLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.pending)
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(P.accentLight),
                ),
              ),
            )
          else
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
          if (item.retryText != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: state.selectedRunning
                    ? null
                    : () => state.sendPrompt(item.retryText!),
                child: const Text('重试'),
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

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.state, required this.images});

  final AppState state;
  final List<ChatImage> images;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: images.isNotEmpty ? 8 : 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final image in images)
            _ChatImageTile(state: state, image: image),
        ],
      ),
    );
  }
}

class _ChatImageTile extends StatefulWidget {
  const _ChatImageTile({required this.state, required this.image});

  final AppState state;
  final ChatImage image;

  @override
  State<_ChatImageTile> createState() => _ChatImageTileState();
}

class _ChatImageTileState extends State<_ChatImageTile> {
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.image.data == null) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final data = await widget.state.loadAttachment(widget.image);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = data == null;
    });
  }

  Uint8List? get _bytes {
    final data = widget.image.data;
    if (data == null) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return GestureDetector(
      onTap: bytes == null
          ? _load
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ImagePreviewPage(bytes: bytes, name: widget.image.name),
              ),
            ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 156,
          height: 156,
          color: P.fillMedium,
          alignment: Alignment.center,
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
              : _loading
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, color: P.textTertiary),
                    const SizedBox(height: 6),
                    Text(
                      _failed ? '加载失败,点击重试' : '点击加载',
                      style: TextStyle(color: P.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({super.key, required this.bytes, this.name});

  final Uint8List bytes;
  final String? name;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final album = 'xHarness';
      await Gal.putImageBytes(widget.bytes, album: album);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已保存到系统相册')));
    } on GalException catch (error) {
      if (!mounted) return;
      final message = error.type == GalExceptionType.accessDenied
          ? '没有相册权限，请在系统设置中允许 xHarness 访问照片'
          : '保存图片失败，请稍后重试';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存图片失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.name ?? '图片预览'),
        actions: [
          IconButton(
            tooltip: '下载图片',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(widget.bytes, fit: BoxFit.contain),
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

class Composer extends StatefulWidget {
  const Composer({super.key, required this.state});

  final AppState state;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<PromptImage> _images = [];
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openCommands() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Without this the sheet caps at half the screen and the sheet's own
      // column cannot scroll, so long server catalogs (e.g. /permission at
      // the tail) were clipped away with no way to reach them.
      isScrollControlled: true,
      builder: (sheetContext) => _CommandsSheet(
        state: widget.state,
        onRun: (command) {
          Navigator.of(sheetContext).pop();
          widget.state.runCommand('/$command');
        },
        onOpenPermissions: () {
          Navigator.of(sheetContext).pop();
          _openPermissions();
        },
        onInsert: (command) {
          Navigator.of(sheetContext).pop();
          _controller.text = '/$command ';
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
          _focusNode.requestFocus();
        },
      ),
    );
  }

  void _openQueue() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TaskQueueSheet(state: widget.state),
    );
  }

  Future<void> _pickImage() async {
    if (_picking || _images.length >= 4) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw StateError('无法读取图片');
      final normalized = img.bakeOrientation(decoded);
      final encoded = img.encodeJpg(normalized, quality: 88);
      if (encoded.length > 8 * 1024 * 1024) {
        throw StateError('图片超过 8 MB,请换一张');
      }
      if (!mounted) return;
      setState(() {
        _images.add(
          PromptImage(
            mediaType: 'image/jpeg',
            data: base64Encode(encoded),
            name: picked.name,
            width: normalized.width,
            height: normalized.height,
          ),
        );
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $error')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openPermissions() async {
    final preset = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _PermissionSheet(
        onPick: (preset) => Navigator.of(sheetContext).pop(preset),
      ),
    );
    if (preset == null || !mounted) return;
    if (preset == 'danger-full-access') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('开启完全访问?'),
          content: const Text('开启后 DSH 可读写设备上的所有文件，并且不再弹出审批确认。仅在信任当前任务时开启。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开启'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.state.runCommand('/permission $preset');
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    final images = List<PromptImage>.of(_images);
    _controller.clear();
    setState(() => _images.clear());
    HapticFeedback.lightImpact();
    if (text.startsWith('/') && images.isEmpty) {
      // Slash commands render their own echo + progress + result in chat.
      widget.state.runCommand(text);
      return;
    }
    final sent = await widget.state.sendPrompt(text, images: images);
    if (!sent && mounted) {
      setState(() {
        if (_controller.text.isEmpty) _controller.text = text;
        _images.insertAll(0, images);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.state.selectedSessionId != null;
    final canSend =
        enabled && (_controller.text.trim().isNotEmpty || _images.isNotEmpty);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: P.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: P.isDark ? P.fillMedium : P.divider),
            boxShadow: P.cardShadow,
          ),
          padding: const EdgeInsets.only(left: 4, right: 6, top: 5, bottom: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_images.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 10, bottom: 5),
                      itemCount: _images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final image = _images[index];
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(image.data),
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.cancel, size: 19),
                                color: P.danger,
                                onPressed: () =>
                                    setState(() => _images.removeAt(index)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: IconButton(
                      tooltip: '快捷命令',
                      icon: const Icon(Icons.add_circle_outline),
                      color: P.textSecondary,
                      onPressed: enabled ? _openCommands : null,
                    ),
                  ),
                  if (widget.state.hasQueuedTasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Badge(
                        label: Text('${widget.state.pendingTaskCount}'),
                        child: IconButton(
                          tooltip: '任务队列',
                          icon: const Icon(Icons.playlist_play_rounded),
                          color: P.accentLight,
                          onPressed: enabled ? _openQueue : null,
                        ),
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 15.5),
                      decoration: InputDecoration(
                        hintText: enabled ? '发消息给 DSH…' : '先选择或新建一个会话',
                        hintStyle: TextStyle(color: P.textTertiary),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (widget.state.selectedRunning)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: P.danger.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: P.danger.withValues(alpha: 0.5),
                          ),
                        ),
                        child: IconButton(
                          tooltip: '停止生成',
                          icon: Icon(Icons.stop_rounded, color: P.danger),
                          onPressed: () => widget.state.cancelTurn(),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: IconButton(
                      tooltip: '添加图片',
                      icon: _picking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                      color: P.textSecondary,
                      onPressed: enabled && !_picking && _images.length < 4
                          ? _pickImage
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    // Container, not Ink: on Xiaomi HyperOS the Ink+gradient
                    // decoration silently fails to paint, leaving the white
                    // (onAccent) arrow on a white card — an invisible but still
                    // tappable send button (v1.10.0 field report).
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: canSend ? P.brandGradient : null,
                        color: canSend ? null : P.fillLight,
                        shape: BoxShape.circle,
                        boxShadow: canSend ? [P.brandGlow] : null,
                      ),
                      child: IconButton(
                        tooltip: '发送',
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          color: canSend ? P.onAccent : P.textTertiary,
                        ),
                        onPressed: canSend ? _send : null,
                      ),
                    ),
                  ),
                ],
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
                  child: _MiniChip(
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

/// One slash command offered by the composer sheet.
class _SlashCommand {
  const _SlashCommand(
    this.name,
    this.icon,
    this.description, {
    this.hasInput = false,
  });

  final String name;
  final IconData icon;
  final String description;

  /// Commands with input insert the prefix instead of sending directly.
  final bool hasInput;
}

const _slashCommands = [
  _SlashCommand('compact', Icons.compress, '压缩较早的对话历史,释放上下文空间'),
  _SlashCommand('plan', Icons.map_outlined, '进入或退出计划模式'),
  _SlashCommand('goal', Icons.flag_outlined, '设置或查看长期任务目标', hasInput: true),
  _SlashCommand(
    'permission',
    Icons.shield_outlined,
    '切换权限模式(如 /permission danger-full-access)',
    hasInput: true,
  ),
  _SlashCommand(
    'feedback',
    Icons.rate_review_outlined,
    '记录对本会话的反馈',
    hasInput: true,
  ),
];

/// One entry of the "更多功能" grid sheet.
class _MoreAction {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.dot = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Small tertiary text under the label (e.g. the current theme name).
  final String? caption;

  /// Green badge dot on the icon (update available).
  final bool dot;

  /// Danger styling (logout).
  final bool danger;
}

/// The "更多功能" bottom sheet: a 4-column icon grid holding every utility
/// that used to be a full-height drawer tile.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.actions});

  final List<_MoreAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '更多功能',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.92,
              children: [
                for (final action in actions) _MoreCell(action: action),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreCell extends StatelessWidget {
  const _MoreCell({required this.action});

  final _MoreAction action;

  @override
  Widget build(BuildContext context) {
    final fg = action.danger ? P.danger : P.accentLight;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: action.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: action.danger
                      ? P.danger.withValues(alpha: 0.1)
                      : P.fillSubtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, size: 22, color: fg),
              ),
              if (action.dot)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: P.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: P.card, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            style: TextStyle(
              fontSize: 12,
              color: action.danger ? P.danger : P.textSecondary,
            ),
          ),
          if (action.caption != null)
            Text(
              action.caption!,
              style: TextStyle(fontSize: 10, color: P.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// Permission-mode sheet (drawer → 权限模式): one tap per preset; the pick
/// rides the /permission command, so the chat shows the usual command card.
class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({required this.onPick});

  /// Called with the chosen preset name ('workspace-write' etc.).
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '权限模式',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '控制当前会话的文件访问范围与审批策略',
              style: TextStyle(fontSize: 12, color: P.textTertiary),
            ),
            const SizedBox(height: 12),
            _PermissionOption(
              icon: Icons.edit_note,
              title: '工作区写入',
              preset: 'workspace-write',
              description: '只能写当前工作区;越权操作会先弹审批询问你',
              onPick: onPick,
            ),
            const SizedBox(height: 6),
            _PermissionOption(
              icon: Icons.lock_open_outlined,
              title: '完全访问',
              preset: 'danger-full-access',
              description: '全部文件可读写,且不再弹审批(需二次确认)',
              onPick: onPick,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionOption extends StatelessWidget {
  const _PermissionOption({
    required this.icon,
    required this.title,
    required this.preset,
    required this.description,
    required this.onPick,
  });

  final IconData icon;
  final String title;

  /// Preset name passed to /permission.
  final String preset;
  final String description;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: P.fillSubtle,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: P.brandGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: P.onAccent),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          description,
          style: TextStyle(fontSize: 12, color: P.textSecondary),
        ),
        onTap: () => onPick(preset),
      ),
    );
  }
}

/// Server-authoritative pending task list for the selected session.
class _TaskQueueSheet extends StatelessWidget {
  const _TaskQueueSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final tasks = state.queuedTasks;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '任务队列',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '待处理 ${state.pendingTaskCount} 个',
                      style: TextStyle(color: P.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'AI 完成当前任务后，会按顺序自动继续处理。',
                  style: TextStyle(color: P.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '当前没有排队任务',
                        style: TextStyle(color: P.textSecondary),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.55,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final task = tasks[index];
                        final label = task.placement == 'steering'
                            ? '即将插入'
                            : '排队 ${index + 1}';
                        final content = task.text.trim().isEmpty
                            ? (task.imageCount > 0
                                  ? '[${task.imageCount} 张图片]'
                                  : '无文字任务')
                            : task.text;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: P.fillSubtle,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: P.divider),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: P.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: P.accentLight,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: P.textTertiary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      content,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (task.imageCount > 0 &&
                                        task.text.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '附带 ${task.imageCount} 张图片',
                                          style: TextStyle(
                                            color: P.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Quick-command sheet opened from the composer's + button. The catalog
/// loads live from the host (commands/list); the built-in list is the
/// offline fallback.
class _CommandsSheet extends StatefulWidget {
  const _CommandsSheet({
    required this.state,
    required this.onRun,
    required this.onInsert,
    required this.onOpenPermissions,
  });

  final AppState state;

  /// Executes `/<name>` immediately.
  final ValueChanged<String> onRun;

  /// Inserts `/<name> ` into the composer for argument entry.
  final ValueChanged<String> onInsert;

  /// Opens the current session's permission preset picker.
  final VoidCallback onOpenPermissions;

  @override
  State<_CommandsSheet> createState() => _CommandsSheetState();
}

class _CommandsSheetState extends State<_CommandsSheet> {
  List<_SlashCommand> _commands = _slashCommands;

  static const _icons = <String, IconData>{
    'compact': Icons.compress,
    'plan': Icons.map_outlined,
    'goal': Icons.flag_outlined,
    'feedback': Icons.rate_review_outlined,
    'export': Icons.download_outlined,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.state.listCommands();
      if (!mounted || catalog.isEmpty) return;
      setState(() {
        _commands = [
          for (final entry in catalog)
            _SlashCommand(
              entry['name'] as String? ?? '',
              _icons[entry['name']] ?? Icons.terminal,
              entry['description'] as String? ?? '',
              hasInput: entry['input'] != null,
            ),
        ];
      });
    } catch (_) {
      // Keep the built-in fallback list.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快捷命令',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '以 / 开头的消息会作为命令执行,不会发送给模型',
              style: TextStyle(fontSize: 12, color: P.textTertiary),
            ),
            const SizedBox(height: 12),
            Material(
              color: P.fillSubtle,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: P.isDark
                        ? P.success.withValues(alpha: 0.18)
                        : P.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: P.success,
                  ),
                ),
                title: const Text(
                  '权限模式',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '切换工作区写入或完全访问',
                  style: TextStyle(fontSize: 12, color: P.textSecondary),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: P.textTertiary,
                ),
                onTap: widget.onOpenPermissions,
              ),
            ),
            const SizedBox(height: 12),
            // Bounded, scrollable list: the catalog comes from the server and
            // grows over time; a fixed Column clipped past the sheet height.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final command in _commands)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: P.fillSubtle,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: P.brandGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              command.icon,
                              size: 18,
                              color: P.onAccent,
                            ),
                          ),
                          title: Text(
                            '/${command.name}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            command.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: P.textSecondary,
                            ),
                          ),
                          trailing: Icon(
                            command.hasInput
                                ? Icons.edit_outlined
                                : Icons.play_arrow_rounded,
                            size: 18,
                            color: P.textTertiary,
                          ),
                          onTap: () => command.hasInput
                              ? widget.onInsert(command.name)
                              : widget.onRun(command.name),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

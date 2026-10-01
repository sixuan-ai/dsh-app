/// Server setup and account connection page.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand_mark.dart';
import 'connection_guide.dart';
import 'src/protocol.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({
    super.key,
    required this.state,
    required this.defaultServerUrl,
  });

  final AppState state;
  final String defaultServerUrl;

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _lanUrl = TextEditingController();
  String _connectionMode = 'public';
  bool _obscurePass = true;

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
      final storedMode = prefs.getString('connectionMode') ?? 'public';
      // The login page only models public/LAN; other stored modes (e.g. the
      // direct Shenzhen relay) present as public until the user re-picks.
      _connectionMode = storedMode == 'lan' ? 'lan' : 'public';
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
    var serverUrl = widget.defaultServerUrl;
    if (_connectionMode == 'lan') {
      serverUrl = _normalizeServerUrl(_lanUrl.text);
      if (serverUrl.isEmpty) {
        setState(() => _preError = '请输入电脑的本地网络地址');
        return;
      }
    } else {
      // Public login resolves the account's instance through the central directory.
      try {
        serverUrl = await directoryLogin(widget.defaultServerUrl, user, pass);
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
    final host = Uri.parse(widget.defaultServerUrl).host;
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
                        const BrandMark(size: 84),
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
                          S.tagline,
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
                                segments: [
                                  ButtonSegment(
                                    value: 'public',
                                    icon: const Icon(Icons.public),
                                    label: Text(S.remoteConnection),
                                  ),
                                  ButtonSegment(
                                    value: 'lan',
                                    icon: const Icon(Icons.wifi),
                                    label: Text(S.localConnection),
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
                                            ? S.lanHomeDesc
                                            : S.remoteOutDesc,
                                        style: TextStyle(
                                          color: P.textSecondary,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _showConnectionGuide(),
                                      child: Text(S.howToConfig),
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
                                      Expanded(
                                        child: Text(
                                          S.lanSecurityWarning,
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
                                    S.lanUrlHint,
                                    Icons.lan_outlined,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextField(
                                controller: _user,
                                autofillHints: const [AutofillHints.username],
                                decoration: _loginDecoration(
                                  S.username,
                                  Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pass,
                                obscureText: _obscurePass,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _connect(),
                                decoration:
                                    _loginDecoration(
                                      S.password,
                                      Icons.lock_outline,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePass
                                            ? S.showPassword
                                            : S.hidePassword,
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 19,
                                          color: P.textTertiary,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass,
                                        ),
                                      ),
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
                              GradientActionButton(
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
class GradientActionButton extends StatelessWidget {
  const GradientActionButton({
    super.key,
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
          boxShadow: enabled ? [P.brandGlow] : null,
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

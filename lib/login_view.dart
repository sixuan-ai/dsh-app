/// Account login; computer and network selection live in connection settings.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'brand_mark.dart';
import 'register_view.dart';
import 'connector_pairing_page.dart';
import 'src/protocol.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'state.dart';

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({
    super.key,
    required this.state,
    required this.defaultServerUrl,
    this.initialError,
    this.onConnected,
  });
  final AppState state;
  final String defaultServerUrl;
  final String? initialError;
  final VoidCallback? onConnected;
  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscurePass = true;
  bool _submitting = false;
  String? _preError;

  @override
  void initState() {
    super.initState();
    _preError = widget.initialError;
    _prefill();
  }

  Future<void> _prefill() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _user.text.isNotEmpty) return;
    _user.text = prefs.getString('authUser') ?? '';
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_submitting || widget.state.connecting) return;
    final user = _user.text.trim();
    final pass = _pass.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _preError = '请输入邮箱或用户名和密码');
      return;
    }
    setState(() {
      _submitting = true;
      _preError = null;
    });
    try {
      final login = await directoryLogin(
        widget.defaultServerUrl,
        user,
        pass,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (widget.state.pairedComputer != null) {
        await widget.state.useAccountConnection();
      }
      await widget.state.setComputers(login.computers);
      final prefs = await SharedPreferences.getInstance();
      final previousUser = prefs.getString('authUser');
      if (previousUser != null && previousUser != login.username) {
        await widget.state.clearPairedComputers();
      }
      await prefs.setString('authUser', login.username);
      await prefs.setString('authPass', pass);
      await prefs.remove('launchToken');
      await prefs.setString('connectionMode', 'public');
      await prefs.setString('remoteServerUrl', login.defaultUrl);
      await prefs.setString('serverUrl', login.defaultUrl);
      if (!mounted) return;
      await widget.state.acceptLegacyEntry();
      await widget.state.connect(
        login.defaultUrl,
        username: login.username,
        password: pass,
      );
      if (widget.state.connected) widget.onConnected?.call();
    } on DshError catch (error) {
      if (!mounted) return;
      setState(
        () => _preError = switch (error.code) {
          'directory-auth' => '用户名或密码错误',
          'directory-not-provisioned' => '账号已创建，暂未绑定电脑。请联系管理员开通后再登录。',
          _ => '暂时无法登录，请稍后重试。',
        },
      );
    } catch (_) {
      if (mounted) setState(() => _preError = '暂时无法登录，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openRegistration() async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RegisterPage(
          baseUrl: widget.defaultServerUrl,
          suggestedEmail: _user.text.trim(),
        ),
      ),
    );
    if (!mounted || created == null || created.isEmpty) return;
    setState(() {
      _user.text = created;
      _preError = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            P.bg,
            Color.lerp(P.bg, P.accent, P.isDark ? 0.12 : 0.06)!,
            Color.lerp(P.bg, P.accent2, P.isDark ? 0.16 : 0.09)!,
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
                  final busy = _submitting || widget.state.connecting;
                  final error =
                      _preError ??
                      (widget.state.connectionError == null
                          ? null
                          : '暂时无法连接你的电脑，请确认电脑在线后重试。');
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
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              TextField(
                                controller: _user,
                                enabled: !busy,
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                decoration: _loginDecoration(
                                  '邮箱或用户名',
                                  Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pass,
                                enabled: !busy,
                                obscureText: _obscurePass,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _connect(),
                                decoration:
                                    _loginDecoration(
                                      S.password,
                                      Icons.lock_outline,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePass ? '显示密码' : '隐藏密码',
                                        onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass,
                                        ),
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                      ),
                                    ),
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  error,
                                  style: TextStyle(color: P.danger),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 20),
                              GradientActionButton(
                                label: '登录',
                                loading: busy,
                                onPressed: busy ? null : _connect,
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ConnectorPairingPage(
                                            state: widget.state,
                                          ),
                                        ),
                                      ),
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('连接我的电脑'),
                              ),
                              TextButton(
                                onPressed: busy ? null : _openRegistration,
                                child: const Text('还没有账号？用邮箱注册'),
                              ),
                            ],
                          ),
                        ),
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

  InputDecoration _loginDecoration(String label, IconData icon) =>
      InputDecoration(
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

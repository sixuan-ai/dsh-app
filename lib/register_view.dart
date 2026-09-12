/// 企业邮箱注册页:获取验证码 → 校验 → 创建账号。
///
/// 账号本身只是「登录账号」;验证通过不等于已经能在手机上连上 DSH ——
/// 实例(子域名/证书/隧道)需管理员为该账号开通,页面会明确说明这一点。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'src/l10n.dart';
import 'src/protocol.dart';
import 'src/theme.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.baseUrl,
    required this.suggestedEmail,
  });

  /// Directory origin the registration endpoints live under.
  final String baseUrl;

  /// Pre-filled mailbox (typically what the user typed on the login page).
  final String suggestedEmail;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

enum _Step { email, code, done }

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  _Step _step = _Step.email;
  RegistrationConfig? _config;
  String? _error;
  String? _notice;
  bool _busy = false;
  bool _obscure = true;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String _createdUsername = '';
  bool _provisioned = false;
  String _doneMessage = '';

  @override
  void initState() {
    super.initState();
    _email.text = widget.suggestedEmail;
    unawaited(_loadConfig());
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await fetchRegistrationConfig(widget.baseUrl);
      if (!mounted) return;
      setState(() => _config = config);
    } on DshError catch (error) {
      if (!mounted) return;
      // A missing config endpoint must not block the page: fall back to the
      // generic rules and let the request itself report the real problem.
      setState(() => _error = error.code == 'directory-unavailable'
          ? '暂时无法连接注册服务,请稍后再试'
          : error.message);
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  bool get _emailLooksRight {
    final value = _email.text.trim().toLowerCase();
    if (!value.contains('@')) return false;
    final domains = _config?.domains ?? const <String>[];
    if (domains.isEmpty) return true;
    return domains.any((d) => value.endsWith('@$d'));
  }

  String get _domainHint {
    final domains = _config?.domains ?? const <String>[];
    if (domains.isEmpty) return '请输入企业邮箱';
    return '仅限 ${domains.map((d) => '@$d').join(' / ')}';
  }

  Future<void> _sendCode() async {
    if (_busy || _cooldown > 0) return;
    final email = _email.text.trim().toLowerCase();
    if (!_emailLooksRight) {
      setState(() => _error = _domainHint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await requestRegistrationCode(widget.baseUrl, email);
      if (!mounted) return;
      setState(() {
        _step = _Step.code;
        final seconds = _config?.mailEnabled == false ? 0 : 60;
        _notice = _config?.mailEnabled == false
            ? '服务端尚未配置发信,验证码请向管理员索取'
            : '验证码已发送,请查收邮件(含垃圾箱)';
        if (seconds > 0) _startCooldown(seconds);
      });
    } on DshError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final email = _email.text.trim().toLowerCase();
    final code = _code.text.trim();
    final pass = _pass.text;
    final minLen = _config?.minPassword ?? 8;
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    if (pass.length < minLen) {
      setState(() => _error = '密码至少 $minLen 位');
      return;
    }
    if (pass != _pass2.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await verifyRegistrationCode(
        widget.baseUrl,
        email: email,
        code: code,
        password: pass,
      );
      if (!mounted) return;
      setState(() {
        _step = _Step.done;
        _createdUsername = result.username;
        _provisioned = result.provisioned;
        _doneMessage = result.message;
      });
    } on DshError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 20),
              switch (_step) {
                _Step.email => _emailStep(),
                _Step.code => _codeStep(),
                _Step.done => _doneStep(),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '使用企业邮箱注册',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: P.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '注册后即可用它登录。连接到你自己的电脑还需管理员开通实例。',
          style: TextStyle(fontSize: 13, height: 1.5, color: P.textSecondary),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    int? maxLength,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        maxLength: maxLength,
        enabled: !_busy,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    final error = _error;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: P.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: P.danger.withValues(alpha: 0.30)),
        ),
        child: Text(
          error,
          style: TextStyle(fontSize: 13, height: 1.4, color: P.danger),
        ),
      ),
    );
  }

  Widget _noticeBox() {
    final notice = _notice;
    if (notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: P.fillLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          notice,
          style: TextStyle(fontSize: 13, height: 1.4, color: P.textSecondary),
        ),
      ),
    );
  }

  Widget _primary(String label, VoidCallback? onPressed) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: _busy ? null : onPressed,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          controller: _email,
          label: '企业邮箱',
          hint: 'name@company.com',
          keyboard: TextInputType.emailAddress,
          onSubmitted: (_) => _sendCode(),
        ),
        Text(
          _domainHint,
          style: TextStyle(fontSize: 12, color: P.textTertiary),
        ),
        const SizedBox(height: 16),
        _errorBox(),
        _primary('获取验证码', _sendCode),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _email.text.trim(),
                style: TextStyle(fontSize: 13, color: P.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _step = _Step.email;
                        _error = null;
                        _notice = null;
                      }),
              child: const Text('换个邮箱'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _noticeBox(),
        _field(
          controller: _code,
          label: '验证码',
          hint: '6 位数字',
          keyboard: TextInputType.number,
          maxLength: 6,
        ),
        _field(
          controller: _pass,
          label: '设置密码',
          hint: '至少 ${_config?.minPassword ?? 8} 位',
          obscure: _obscure,
          suffix: IconButton(
            tooltip: _obscure ? S.showPassword : S.hidePassword,
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 19,
              color: P.textTertiary,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        _field(
          controller: _pass2,
          label: '确认密码',
          obscure: _obscure,
          onSubmitted: (_) => _verify(),
        ),
        _errorBox(),
        _primary('创建账号', _verify),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: (_busy || _cooldown > 0) ? null : _sendCode,
            child: Text(
              _cooldown > 0 ? '重新获取（$_cooldown 秒）' : '重新获取验证码',
            ),
          ),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 44, color: P.accentLight),
        const SizedBox(height: 12),
        Text(
          '账号已创建',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: P.text,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: P.fillLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '登录用户名：$_createdUsername',
                style: TextStyle(fontSize: 13, color: P.text),
              ),
              const SizedBox(height: 4),
              Text(
                '也可以用邮箱登录',
                style: TextStyle(fontSize: 12, color: P.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _provisioned
              ? '实例已就绪,可以直接登录使用。'
              : '你的账号已可以用邮箱登录,但还没有可连接的电脑实例。'
                  '请让管理员为它开通实例,之后即可在手机上连接自己的 DSH。',
          style: TextStyle(fontSize: 13, height: 1.5, color: P.textSecondary),
        ),
        if (_doneMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _doneMessage,
            style: TextStyle(fontSize: 12, color: P.textTertiary),
          ),
        ],
        const SizedBox(height: 20),
        _primary('返回登录', () {
          Navigator.of(context).pop(_createdUsername);
        }),
      ],
    );
  }
}

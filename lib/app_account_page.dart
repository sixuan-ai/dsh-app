/// Optional native Sixuan account entry, separate from desktop transport.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'src/theme.dart';
import 'src/ui/glass.dart';
import 'package:flutter/services.dart';
import 'login_view.dart';
import 'src/protocol.dart' show kDefaultServerUrl;
import 'src/sixuan_account.dart';
import 'state.dart';
import 'access_policy.dart';

enum AppAccountMode { welcome, login, register, recover }

class AppAccountPage extends StatefulWidget {
  const AppAccountPage({
    super.key,
    required this.state,
    this.initialMode = AppAccountMode.welcome,
    this.allowGuest = true,
    this.onCompleted,
    this.initialError,
  });
  final AppState state;
  final AppAccountMode initialMode;
  final bool allowGuest;
  final VoidCallback? onCompleted;
  final String? initialError;
  @override
  State<AppAccountPage> createState() => _AppAccountPageState();
}

class _AppAccountPageState extends State<AppAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  var _form = GlobalKey<FormState>();
  late AppAccountMode _mode;
  late String _deviceId;
  String? _secret, _error, _notice;
  bool _busy = false, _obscure = true, _remember = false, _complete = false;
  int _cooldown = 0;
  Timer? _timer;
  String get _modeName => _mode.name;
  bool get _verification => _secret != null;
  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _deviceId = widget.state.identityApi.newDeviceId();
    _error = widget.initialError;
    _email.text = widget.state.signedInAccount?.email ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_email, _password, _confirm, _name, _code]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _change(AppAccountMode mode) {
    if (_busy) return;
    _timer?.cancel();
    setState(() {
      _form = GlobalKey<FormState>();
      _mode = mode;
      _secret = null;
      _error = _notice = null;
      _complete = false;
      _password.clear();
      _confirm.clear();
      _code.clear();
      _cooldown = 0;
      _obscure = true;
    });
  }

  void _countdown() {
    _timer?.cancel();
    _cooldown = 60;
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _guest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.state.enterGuestMode();
      if (mounted) widget.onCompleted?.call();
    } catch (_) {
      if (mounted) setState(() => _error = '无法保存使用模式，请解锁手机后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == AppAccountMode.login) {
        final result = await widget.state.identityApi.passwordLogin(
          email: _email.text.trim(),
          password: _password.text,
          deviceId: _deviceId,
          remember: _remember,
        );
        if (!mounted) return;
        final session = widget.state.identityApi.sessionFromResult(
          result,
          remember: _remember,
        );
        await widget.state.acceptAccountSession(session);
        _password.clear();
        if (mounted) widget.onCompleted?.call();
      } else if (!_verification) {
        final result = await widget.state.identityApi.requestCode(
          mode: _modeName,
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          deviceId: _deviceId,
        );
        if (!mounted) return;
        final secret = result['secret'];
        if (secret is! String || secret.isEmpty) {
          throw const SixuanAccountError('验证码服务返回异常，请重试');
        }
        setState(() {
          _secret = secret;
          _password.clear();
          _confirm.clear();
          _notice = _mode == AppAccountMode.recover
              ? '如果邮箱已注册，验证码会发送到邮箱。'
              : _mode == AppAccountMode.register
              ? '若邮箱可注册，验证码会发送到邮箱；已有账号请登录。'
              : '验证码已发送，请在 5 分钟内填写。';
          _countdown();
        });
      } else {
        final result = await widget.state.identityApi.verifyCode(
          mode: _modeName,
          secret: _secret!,
          code: _code.text.trim(),
          deviceId: _deviceId,
          remember: _remember,
          password: _mode == AppAccountMode.recover ? _password.text : null,
        );
        if (!mounted) return;
        if (_mode == AppAccountMode.login) {
          final session = widget.state.identityApi.sessionFromResult(
            result,
            remember: _remember,
          );
          await widget.state.acceptAccountSession(session);
          if (mounted) widget.onCompleted?.call();
        } else {
          if (!mounted) return;
          _timer?.cancel();
          setState(() {
            _secret = null;
            _complete = true;
            _code.clear();
            _password.clear();
            _confirm.clear();
            _notice = _mode == AppAccountMode.recover
                ? '密码已重置，请使用新密码登录。'
                : '账号已创建，可直接使用邮箱和密码登录。';
          });
        }
      }
    } on SixuanAccountError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法完成操作，请检查网络或解锁手机后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _legacy() async {
    final navigator = Navigator.of(context);
    final completed = widget.onCompleted;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ServerSetupPage(
          state: widget.state,
          defaultServerUrl: kDefaultServerUrl,
          onConnected: () {
            navigator.pop();
            completed?.call();
          },
        ),
      ),
    );
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    bool password = false,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: Theme.of(context).brightness == Brightness.dark
        ? P.code
        : P.code,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: P.textTertiary.withValues(alpha: .2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: P.textTertiary.withValues(alpha: .16)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: P.accent, width: 1.5),
    ),
    suffixIcon: password
        ? IconButton(
            tooltip: _obscure ? '显示密码' : '隐藏密码',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
            ),
          )
        : null,
  );
  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool password = false,
    bool confirmation = false,
    bool email = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: password && _obscure,
      autocorrect: !password && !email,
      enableSuggestions: !password && !email,
      // WeType can keep its hardware-candidate view for emailAddress after
      // injected/physical key events. Standard text keeps the full soft IME.
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.none,
      textInputAction: email ? TextInputAction.next : TextInputAction.done,
      autofillHints: email
          ? [AutofillHints.username]
          : password
          ? [
              _mode == AppAccountMode.login
                  ? AutofillHints.password
                  : AutofillHints.newPassword,
            ]
          : null,
      decoration: _decoration(label, icon, password: password && !confirmation),
      validator: (value) {
        final text = value ?? '';
        if (email &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text.trim())) {
          return '请输入有效邮箱';
        }
        if (password && text.isEmpty) return '请输入密码';
        if (password &&
            _mode != AppAccountMode.login &&
            (text.length < 12 || text.length > 128)) {
          return '密码需为 12～128 个字符';
        }
        if (confirmation && text != _password.text) return '两次输入的密码不一致';
        return null;
      },
    ),
  );
  Widget _action(
    String label,
    VoidCallback? action, {
    bool primary = true,
  }) => SizedBox(
    width: double.infinity,
    child: primary
        ? FilledButton(
            onPressed: _busy ? null : action,
            style: FilledButton.styleFrom(
              backgroundColor: P.accent,
              foregroundColor: P.onAccent,
              minimumSize: const Size(0, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: _busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label, style: TextStyle(fontWeight: FontWeight.w700)),
          )
        : OutlinedButton(
            onPressed: _busy ? null : action,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).brightness == Brightness.dark
                  ? P.accent
                  : P.text,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Text(label),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    final ink = P.text;
    final muted = P.textSecondary;
    return Scaffold(
      backgroundColor: dark ? P.bg : P.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -130,
              left: -180,
              child: IgnorePointer(
                child: Container(
                  width: 430,
                  height: 430,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        P.accent.withValues(alpha: dark ? .06 : .14),
                        P.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      children: [
                        if (!widget.allowGuest)
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: P.accent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.all_inclusive_rounded,
                            color: P.text,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'xHarness',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!compact)
                          Text(
                            '本地优先',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                      ],
                    ),
                    SizedBox(height: 36),
                    AnimatedBuilder(
                      animation: widget.state,
                      builder: (context, _) {
                        final account = widget.state.signedInAccount;
                        if (account != null) {
                          return _card(
                            dark,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  size: 36,
                                  color: P.accent,
                                ),
                                SizedBox(height: 18),
                                Text(
                                  '我的思玄账号',
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  account.name,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                Text(
                                  account.email,
                                  style: TextStyle(color: muted),
                                ),
                                SizedBox(height: 24),
                                Text(
                                  widget.state.identityNotice ??
                                      '可使用局域网和已配置的公网入口',
                                  style: TextStyle(color: muted),
                                ),
                                SizedBox(height: 18),
                                _action('退出账号，保留电脑连接', () async {
                                  await widget.state.signOutAppAccount();
                                  if (mounted) widget.onCompleted?.call();
                                }, primary: false),
                              ],
                            ),
                          );
                        }
                        if (_mode == AppAccountMode.welcome) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '连接你的电脑，\n继续你的工作。',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 33,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              SizedBox(height: 14),
                              Text(
                                '无需登录即可使用局域网与公网。登录可选，用于账号同步与注册。',
                                style: TextStyle(color: muted, height: 1.8),
                              ),
                              SizedBox(height: 28),
                              _card(
                                dark,
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.wifi_rounded,
                                      size: 32,
                                      color: P.accent,
                                    ),
                                    SizedBox(height: 14),
                                    Text(
                                      '局域网直连',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 7),
                                    Text(
                                      '无需登录，支持多电脑、任务与模型选择。',
                                      style: TextStyle(color: muted),
                                    ),
                                    SizedBox(height: 16),
                                    _action('不登录，先连接', _guest),
                                  ],
                                ),
                              ),
                              SizedBox(height: 18),
                              _card(
                                dark,
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '使用思玄账号',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 7),
                                    Text(
                                      '与官网使用同一套邮箱认证，登录可选用于账号同步与注册。公网连接仍遵循电脑端配对与授权。',
                                      style: TextStyle(
                                        color: muted,
                                        height: 1.7,
                                      ),
                                    ),
                                    SizedBox(height: 18),
                                    if (compact) ...[
                                      _action(
                                        '邮箱登录',
                                        () => _change(AppAccountMode.login),
                                        primary: false,
                                      ),
                                      SizedBox(height: 10),
                                      _action(
                                        '邮箱注册',
                                        () => _change(AppAccountMode.register),
                                        primary: false,
                                      ),
                                    ] else
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _action(
                                              '邮箱登录',
                                              () =>
                                                  _change(AppAccountMode.login),
                                              primary: false,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: _action(
                                              '邮箱注册',
                                              () => _change(
                                                AppAccountMode.register,
                                              ),
                                              primary: false,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        return _card(
                          dark,
                          Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!_verification && !_complete) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final mode in [
                                        AppAccountMode.login,
                                        AppAccountMode.register,
                                        AppAccountMode.recover,
                                      ])
                                        ChoiceChip(
                                          label: Text(
                                            mode == AppAccountMode.login
                                                ? '登录'
                                                : mode ==
                                                      AppAccountMode.register
                                                ? '注册'
                                                : '找回密码',
                                          ),
                                          selectedColor: P.accent,
                                          labelStyle: TextStyle(
                                            color: _mode == mode ? P.text : ink,
                                          ),
                                          selected: _mode == mode,
                                          showCheckmark: false,
                                          onSelected: _busy
                                              ? null
                                              : (_) => _change(mode),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 24),
                                ],
                                Text(
                                  _complete
                                      ? (_mode == AppAccountMode.recover
                                            ? '密码已重置'
                                            : '账号已创建')
                                      : _verification
                                      ? '验证你的邮箱'
                                      : switch (_mode) {
                                          AppAccountMode.register => '创建思玄账号',
                                          AppAccountMode.recover => '找回密码',
                                          _ => '欢迎回来',
                                        },
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  _verification
                                      ? _email.text.trim()
                                      : _mode == AppAccountMode.login
                                      ? '使用邮箱和密码登录，无需邮件验证码。'
                                      : '邮箱验证，确认是你。',
                                  style: TextStyle(color: muted),
                                ),
                                SizedBox(height: 24),
                                if (_complete)
                                  _action(
                                    '继续登录',
                                    () => _change(AppAccountMode.login),
                                  )
                                else ...[
                                  if (!_verification) ...[
                                    _field(
                                      _email,
                                      '邮箱',
                                      Icons.mail_outline_rounded,
                                      email: true,
                                    ),
                                    if (_mode == AppAccountMode.register)
                                      _field(
                                        _name,
                                        '称呼（选填）',
                                        Icons.person_outline,
                                      ),
                                    if (_mode != AppAccountMode.recover)
                                      _field(
                                        _password,
                                        '密码',
                                        Icons.lock_outline,
                                        password: true,
                                      ),
                                    if (_mode == AppAccountMode.register)
                                      _field(
                                        _confirm,
                                        '确认密码',
                                        Icons.lock_outline,
                                        password: true,
                                        confirmation: true,
                                      ),
                                    if (_mode == AppAccountMode.login)
                                      Material(
                                        color: P.transparent,
                                        child: CheckboxListTile(
                                          contentPadding: EdgeInsets.zero,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          value: _remember,
                                          onChanged: _busy
                                              ? null
                                              : (value) => setState(
                                                  () => _remember =
                                                      value ?? false,
                                                ),
                                          title: Text(
                                            '保持登录 7 天',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ),
                                  ] else ...[
                                    TextFormField(
                                      controller: _code,
                                      enabled: !_busy,
                                      keyboardType: TextInputType.number,
                                      autofillHints: [
                                        AutofillHints.oneTimeCode,
                                      ],
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6),
                                      ],
                                      decoration: _decoration(
                                        '六位邮件验证码',
                                        Icons.password_rounded,
                                      ),
                                      validator: (value) =>
                                          RegExp(
                                            r'^\d{6}$',
                                          ).hasMatch(value ?? '')
                                          ? null
                                          : '请输入六位验证码',
                                    ),
                                    SizedBox(height: 16),
                                    if (_mode == AppAccountMode.recover) ...[
                                      _field(
                                        _password,
                                        '新密码',
                                        Icons.lock_outline,
                                        password: true,
                                      ),
                                      _field(
                                        _confirm,
                                        '确认新密码',
                                        Icons.lock_outline,
                                        password: true,
                                        confirmation: true,
                                      ),
                                    ],
                                  ],
                                  _action(
                                    _verification
                                        ? (_mode == AppAccountMode.recover
                                              ? '验证并重置密码'
                                              : _mode == AppAccountMode.register
                                              ? '验证并创建账号'
                                              : '验证并登录')
                                        : _mode == AppAccountMode.login
                                        ? '登录'
                                        : '获取邮件验证码',
                                    _submit,
                                  ),
                                  if (_verification)
                                    TextButton(
                                      onPressed: _busy || _cooldown > 0
                                          ? null
                                          : () => _change(_mode),
                                      child: Text(
                                        _cooldown > 0
                                            ? '重新获取（$_cooldown 秒）'
                                            : '重新获取验证码',
                                      ),
                                    ),
                                  if (_mode == AppAccountMode.login &&
                                      !_verification)
                                    Center(
                                      child: TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _change(
                                                AppAccountMode.recover,
                                              ),
                                        child: const Text('忘记密码？'),
                                      ),
                                    ),
                                ],
                                if (_notice != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      _notice!,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                        height: 1.8,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            height: 1.6,
                          ),
                        ),
                      ),
                    if (widget.allowGuest && _mode != AppAccountMode.welcome)
                      TextButton(
                        onPressed: _busy ? null : _guest,
                        child: Text('暂不登录，连接电脑'),
                      ),
                    if (_mode == AppAccountMode.welcome ||
                        widget.state.signedInAccount == null)
                      TextButton(
                        onPressed: _busy ? null : _legacy,
                        child: Text(
                          '已有 DSH 服务账号？',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => showAccessPolicy(context),
                      icon: const Icon(Icons.info_outline_rounded, size: 17),
                      label: const Text('功能与权限'),
                    ),
                    SizedBox(height: 12),
                    Text(
                      kComputerPermissionSummary,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 11, height: 1.7),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(bool dark, Widget child) =>
      GlassPanel(padding: const EdgeInsets.all(24), child: child);
}

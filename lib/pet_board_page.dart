import 'dart:async';
import 'package:flutter/material.dart';
import 'app_account_page.dart';
import 'src/formatters.dart';
import 'src/pet.dart';
import 'src/pet_board.dart';
import 'src/theme.dart';
import 'src/ui/glass.dart';
import 'src/ui/neumorphic.dart';
import 'state.dart';

class PetBoardPage extends StatefulWidget {
  const PetBoardPage({super.key, this.state, this.api, this.onLogin});
  final AppState? state;
  final PetBoardApi? api;
  final VoidCallback? onLogin;
  @override
  State<PetBoardPage> createState() => _PetBoardPageState();
}

class _PetBoardPageState extends State<PetBoardPage> {
  late final PetBoardApi _api;
  PetBoardData? _data;
  String _scope = 'all';
  bool _loading = true;
  String? _error;
  int _request = 0;
  bool get _signedIn => widget.state?.petBoardToken != null;
  @override
  void initState() {
    super.initState();
    _api =
        widget.api ??
        widget.state?.petBoardApi ??
        PetBoardApi(token: () => null);
    _identity = widget.state?.petBoardToken;
    widget.state?.addListener(_identityChanged);
    widget.state?.petBoardReporter.opened();
    unawaited(_load());
  }

  String? _identity;
  void _identityChanged() {
    final identity = widget.state?.petBoardToken;
    if (identity == _identity) return;
    _identity = identity;
    widget.state?.petBoardReporter.opened();
    _data = null;
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    widget.state?.removeListener(_identityChanged);
    if (widget.api == null && widget.state == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final identity = widget.state?.petBoardToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.board(_scope);
      if (!mounted ||
          request != _request ||
          identity != widget.state?.petBoardToken) {
        return;
      }
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = '暂时无法加载排行榜，请稍后重试';
        });
      }
    }
  }

  void _login() {
    if (widget.onLogin != null) {
      widget.onLogin!();
      return;
    }
    final state = widget.state;
    if (state != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => AppAccountPage(state: state)),
      );
    }
  }

  Future<void> _settings() async {
    final settingsIdentity = widget.state?.petBoardToken;
    final me = _data?.me;
    final nickname = TextEditingController(text: me?.nickname ?? '');
    var optedOut = me?.optedOut ?? false;
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('排行榜设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('公开昵称将展示给所有访客。默认使用脱敏邮箱。'),
                TextField(
                  key: const ValueKey('board-nickname'),
                  controller: nickname,
                  maxLength: 16,
                  decoration: const InputDecoration(labelText: '公开昵称（1–16 字）'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('不参与排行'),
                  value: optedOut,
                  onChanged: saving ? null : (v) => update(() => optedOut = v),
                ),
                if (error != null)
                  Text(error!, style: TextStyle(color: P.danger)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final text = nickname.text.trim();
                      final changed = text != (me?.nickname ?? '');
                      if (changed &&
                          (text.runes.isEmpty ||
                              text.runes.length > 16 ||
                              RegExp(r'[\x00-\x1f\x7f]').hasMatch(text))) {
                        update(() => error = '请输入 1–16 字昵称，不能含控制字符');
                        return;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final identity = widget.state?.petBoardToken;
                        if (settingsIdentity != identity) {
                          if (context.mounted) Navigator.pop(context);
                          return;
                        }
                        await _api.settings(changed ? text : null, optedOut);
                        if (!mounted ||
                            identity != widget.state?.petBoardToken) {
                          return;
                        }
                        widget.state?.setPetBoardOptedOut(optedOut);
                        if (context.mounted) Navigator.pop(context);
                        unawaited(_load());
                      } catch (_) {
                        if (context.mounted) {
                          update(() {
                            saving = false;
                            error = '保存失败，请重试';
                          });
                        }
                      }
                    },
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
    // Dispose after route animations have released the TextField.
    Future<void>.delayed(const Duration(seconds: 1), nickname.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final items = _data?.items ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('宠物排行榜'),
        actions: [
          if (_signedIn)
            IconButton(
              tooltip: '排行榜设置',
              onPressed: _settings,
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '一起成长 · 闪耀上榜',
                      style: TextStyle(
                        color: P.accent,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '每 1M token 升一级 · Top 100',
                      style: TextStyle(color: P.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    NeuSegmented(
                      values: const {'all': '总榜', 'week': '本周'},
                      selected: _scope,
                      onSelected: (scope) {
                        if (scope == _scope) return;
                        _scope = scope;
                        _data = null;
                        unawaited(_load());
                      },
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (_scope == 'week')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '本周新增 · 周一 00:00 上海时间重置',
                          style: TextStyle(color: P.textSecondary),
                        ),
                      ),
                    if (_loading) ...[
                      for (var i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NeuSurface(
                            child: Semantics(
                              label: '正在加载排行榜',
                              child: Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: P.code,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ] else if (_error != null)
                      NeuSurface(
                        child: Column(
                          children: [
                            Icon(Icons.cloud_off_rounded, color: P.warning),
                            const SizedBox(height: 12),
                            Text(_error!),
                            TextButton(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    else if (items.isEmpty)
                      const NeuSurface(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('还没有伙伴上榜，成为第一个吧！'),
                        ),
                      )
                    else ...[
                      _podium(items.take(3).toList()),
                      const SizedBox(height: 18),
                      for (final entry in items.skip(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NeuSurface(child: _row(entry)),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: GlassPanel(
                child: _signedIn
                    ? _myRank()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '登录后上榜',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '用思玄账号记录你和大肥鱼的成长',
                            style: TextStyle(color: P.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          NeonButton(
                            label: '前往登录',
                            icon: Icons.login_rounded,
                            onPressed: _login,
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

  Widget _myRank() {
    final me = _data?.me;
    return Column(
      key: const ValueKey('my-pet-rank'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '我的排名${me?.rank == null ? '' : ' · #${me!.rank}'}',
          style: TextStyle(
            color: P.accent,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _loading
              ? '正在同步…'
              : _error != null
              ? '排名暂不可用，下拉重试'
              : me?.optedOut == true
              ? '已关闭参与，可在设置中重新开启'
              : me?.rank == null
              ? '打开宠物页，记录成长后上榜'
              : me!.rank == 1
              ? '你已位居榜首！'
              : '距前一名 ${formatTokens(me.gap)} token',
        ),
      ],
    );
  }

  Widget _podium(List<PetBoardEntry> entries) => LayoutBuilder(
    builder: (context, constraints) {
      final large = MediaQuery.textScalerOf(context).scale(14) > 20;
      final order = entries.length == 3
          ? [entries[1], entries[0], entries[2]]
          : entries;
      final children = [
        for (final e in order)
          Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              color: P.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _medal(e.rank)),
              boxShadow: [
                BoxShadow(
                  color: _medal(e.rank).withValues(alpha: .18),
                  blurRadius: e.rank == 1 ? 24 : 12,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  e.rank == 1
                      ? Icons.emoji_events_rounded
                      : Icons.workspace_premium_rounded,
                  color: _medal(e.rank),
                  size: e.rank == 1 ? 38 : 28,
                ),
                const SizedBox(height: 8),
                Text(
                  '#${e.rank}',
                  style: TextStyle(
                    color: _medal(e.rank),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _PetAvatar(size: 46, ring: _medal(e.rank), glow: true),
                const SizedBox(height: 8),
                Text(
                  e.nickname,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  e.petName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: P.textSecondary, fontSize: 11),
                ),
                Text(
                  'Lv.${e.level}',
                  style: TextStyle(
                    color: P.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  e.stage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: P.textSecondary, fontSize: 11),
                ),
                Text(
                  petRankForScore(e.pkScore).name,
                  style: TextStyle(color: P.warning, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Text(
                  formatTokens(_scope == 'week' ? e.score : e.tokens),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ];
      return large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (final child in children) Expanded(child: child)],
            );
    },
  );
  Color _medal(int? rank) => rank == 1
      ? P.accent
      : rank == 2
      ? P.info
      : P.warning;
  Widget _row(PetBoardEntry e) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 38,
        child: Text('#${e.rank}', style: TextStyle(color: P.textSecondary)),
      ),
      _PetAvatar(size: 34, ring: P.accent.withValues(alpha: .55)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.nickname,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${e.petName} · Lv.${e.level} · ${e.stage}',
              style: TextStyle(color: P.textSecondary, fontSize: 12),
            ),
            Wrap(
              spacing: 10,
              children: [
                Text(
                  '${formatTokens(_scope == 'week' ? e.score : e.tokens)} token',
                  style: TextStyle(color: P.accent),
                ),
                Text(
                  'PK ${petRankForScore(e.pkScore).name}',
                  style: TextStyle(color: P.warning),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// Round BigFish head avatar with a colored ring; replaces the generic
/// waves glyph so rows show the actual companion.
class _PetAvatar extends StatelessWidget {
  const _PetAvatar({required this.size, required this.ring, this.glow = false});

  final double size;
  final Color ring;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: ring, width: 1.5),
      boxShadow: glow
          ? [BoxShadow(color: ring.withValues(alpha: .35), blurRadius: 12)]
          : null,
    ),
    child: ClipOval(
      child: ColoredBox(
        color: P.cardAlt,
        child: Image.asset(
          'assets/pet/dafeiyu/avatar.webp',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) =>
              Icon(Icons.pets_rounded, color: ring, size: size * .5),
        ),
      ),
    ),
  );
}

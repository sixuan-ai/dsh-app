/// Pet page: a local virtual pet (领养/喂食/玩耍/洗澡) rendered entirely from
/// [Pet] state; stats decay in real time via a periodic tick.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pet_sprite.dart';
import 'pet_habitat.dart';
import 'src/pet.dart';
import 'src/theme.dart';
import 'state.dart';

/// Virtual-pet raising page. Owns the [PetStore] round-trips: every mutation
/// saves immediately, and a 1-minute timer applies time decay while open.
/// The growth level derives from the app's cumulative cache-hit input tokens
/// (live via [state] when provided, else the persisted total).
class PetPage extends StatefulWidget {
  const PetPage({super.key, this.state});

  /// App state feeding the live token total; null in tests falls back to the
  /// persisted [PetTokenStore] sum.
  final AppState? state;

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> {
  final _store = PetStore();
  final _tokenStore = PetTokenStore();
  Pet? _pet;

  /// Persisted token total, used when no live [AppState] is attached.
  int _tokensTotal = 0;
  int _riceTokensTotal = 0;
  int get _contextTokens =>
      math.max(_riceTokensTotal, widget.state?.petContextTokensTotal ?? 0);

  void _reconcileRice() {
    final pet = _pet;
    if (pet == null) return;
    final previous = pet.riceBowlsSeen;
    final meals = pet.eatRiceForContext(_contextTokens);
    if (previous != pet.riceBowlsSeen) unawaited(_store.save(pet));
    if (meals > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _actionClip == null) _animate('eat_token');
      });
    }
  }

  /// Null until the first load finishes (distinguishes "loading" from
  /// "no pet yet").
  bool _loaded = false;

  String? _actionClip;
  int _actionId = 0;
  void _animate(String clip) => setState(() {
    _actionClip = clip;
    _actionId++;
  });
  String get _activityClip {
    final state = widget.state;
    if (state == null) return 'idle';
    if (state.approvals.isNotEmpty || state.questions.isNotEmpty) {
      return 'waiting';
    }
    if (!state.connected) return 'idle';
    if (state.selectedRunning) {
      for (final item in state.items.reversed) {
        if (item.kind != ChatItemKind.tool || item.completed) continue;
        final tool = item.name.toLowerCase();
        if (tool.contains('search') || tool.contains('browse')) {
          return 'working_search';
        }
        if (tool.contains('command') ||
            tool.contains('shell') ||
            tool.contains('test')) {
          return 'working_command';
        }
        return 'working';
      }
      return 'thinking';
    }
    if (state.sessions.any((row) => row.running) ||
        state.subagents.any((row) => row.running)) {
      return 'working';
    }
    return 'idle';
  }

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    widget.state?.ensurePetTokensLoaded();
    final pet = await _store.load();
    final tokens = await _tokenStore.total();
    final contextTokens = await _tokenStore.contextTotal();
    final meals = pet?.eatRiceForContext(contextTokens) ?? 0;
    if (!mounted) return;
    setState(() {
      _pet = pet;
      _tokensTotal = tokens;
      _riceTokensTotal = contextTokens;
      if (meals > 0) {
        _actionClip = 'eat_token';
        _actionId++;
      }
      _loaded = true;
    });
    if (pet != null) unawaited(_store.save(pet));
  }

  /// Applies elapsed-time decay and persists; called by the periodic timer.
  void _tick() {
    final pet = _pet;
    if (pet == null || !mounted) return;
    setState(() => pet.applyElapsed(DateTime.now().millisecondsSinceEpoch));
    unawaited(_store.save(pet));
    if (_actionClip == null &&
        _activityClip == 'idle' &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _animate(DateTime.now().minute.isEven ? 'idle_stretch' : 'idle_yawn');
    }
  }

  Future<void> _mutate(
    void Function(Pet pet) action, [
    String clip = 'head_pat',
  ]) async {
    final pet = _pet;
    if (pet == null) return;
    setState(() => action(pet));
    _animate(clip);
    await _store.save(pet);
  }

  Future<void> _play() async {
    var refused = false;
    await _mutate((p) => refused = !p.play(), 'tail');
    if (!mounted) return;
    if (refused) _animate('error');
    if (refused && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('肚子饿啦，先来一碗白米饭吧！')));
    }
  }

  Future<void> _adopt(String name) async {
    // Every adoption starts with the same BigFish companion.
    final pet = Pet.newborn(
      name,
      DateTime.now().millisecondsSinceEpoch,
      speciesId: randomPetSpeciesId(),
    );
    pet.eatRiceForContext(_contextTokens);
    setState(() => _pet = pet);
    await _store.save(pet);
  }

  Future<void> _rename() async {
    final pet = _pet;
    if (pet == null) return;
    final controller = TextEditingController(text: pet.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('给大肥鱼改名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '输入新名字'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && pet.rename(name)) {
      setState(() {});
      await _store.save(pet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PetHabitatColors(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '大肥鱼',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _showRiceRules,
            tooltip: '白米饭与成长规则',
            icon: const Icon(Icons.help_outline_rounded, size: 21),
          ),
          if (_pet != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '改名',
              onPressed: _rename,
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _pet == null
          ? _AdoptView(onAdopt: _adopt)
          : widget.state == null
          ? _buildPetView(context, _pet!)
          // Live tokens (and thus stage/face) come from the state.
          : AnimatedBuilder(
              animation: widget.state!,
              builder: (context, _) {
                _reconcileRice();
                _maybeEvolve();
                return _buildPetView(context, _pet!);
              },
            ),
    );
  }

  Widget _buildPetView(BuildContext context, Pet pet) {
    final animation = _actionClip ?? _activityClip;
    final activity = switch (animation) {
      'eat_token' => '正在吃白米饭',
      'error' => '先来一碗白米饭吧',
      'thinking' => '正在思考',
      'working_search' => '正在查找资料',
      'working_command' => '正在执行任务',
      'working' => '正在工作',
      'waiting' => '等你确认下一步',
      'head_pat' => '被摸摸头，好开心',
      'poke' => '和你打个招呼',
      'tail' => '一起吐泡泡',
      'dragging' => '轻轻拎起来啦',
      'dragging_release' => '稳稳落地',
      'idle_stretch' => '伸个懒腰',
      'idle_yawn' => '打个小哈欠',
      _ => '在这里陪着你',
    };
    return SafeArea(
      top: false,
      child: PetHabitat(
        pet: pet,
        contextTokens: _contextTokens,
        growthTokens: widget.state?.petTokensTotal ?? _tokensTotal,
        activityLabel: activity,
        sprite: GestureDetector(
          onTapUp: (details) =>
              _animate(details.localPosition.dy < 100 ? 'head_pat' : 'poke'),
          onLongPressStart: (_) => _animate('dragging'),
          onLongPressEnd: (_) => _animate('dragging_release'),
          child: PetSprite(
            speciesId: pet.speciesId,
            stageIndex: 0,
            size: 230,
            animation: animation,
            playbackId: _actionId,
            onCompleted: () {
              if (mounted) setState(() => _actionClip = null);
            },
          ),
        ),
        onFeed: () => _mutate((p) => p.feed(), 'eat_token'),
        onPlay: _play,
        onClean: () => _mutate((p) => p.clean(), 'idle_stretch'),
        onBattle: _openBattle,
        onAbout: _showAbout,
        onRules: _showRiceRules,
      ),
    );
  }

  void _showRiceRules() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('白米饭与成长'),
      content: const SingleChildScrollView(
        child: Text(
          '1M 上下文 = 1碗白米饭\n\n'
          '每累计 1,000,000 上下文，大肥鱼自动吃一碗，恢复饱腹与心情。未满一碗的部分会继续累计。\n\n'
          '手动喂白米饭是陪伴互动，不扣上下文，也不会增加累计碗数。\n\n'
          '统计沿用已记录的缓存命中上下文，各会话累计去重；训练奖励保留在成长等级中，不计入饭碗。昵称、等级和历史记录继续保留。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  void _showAbout() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('大肥鱼'),
      content: const SingleChildScrollView(
        child: SelectableText(
          '形象与动画：PC2005-cloud/dsh-pet\nCopyright (c) 2026 PC2005-cloud · MIT\n\n'
          '集成来源：https://github.com/QCYTSN/dsh-dafeiyu\n'
          '使用仓库当前默认形象，保留全部 16 段原始动画。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'XHarness'),
          child: const Text('完整许可证'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  /// Opens the battle dialog against a freshly drawn wild opponent.
  void _openBattle() {
    final pet = _pet;
    if (pet == null) return;
    final tokens = widget.state?.petTokensTotal ?? _tokensTotal;
    showDialog<void>(
      context: context,
      builder: (_) =>
          _BattleDialog(pet: pet, tokens: tokens, onSettle: _settleBattle),
    );
  }

  /// Settles a finished battle: moves the PK score, settles the token stake
  /// into the bonus pool, and refreshes totals so the growth card (and any
  /// level-up evolution) react immediately.
  Future<void> _settleBattle(bool playerWon) async {
    final pet = _pet;
    if (pet == null) return;
    pet.pkScore = math.max(
      0,
      pet.pkScore + (playerWon ? kPetPkScoreWin : kPetPkScoreLose),
    );
    await _store.save(pet);
    final total = await _tokenStore.addBonus(
      playerWon ? kPetBattleStake : -kPetBattleStake,
    );
    await widget.state?.refreshPetTokens();
    if (mounted) setState(() => _tokensTotal = total);
  }

  /// Advances the seen evolution form: silently on first load (old saves
  /// must not celebrate retroactively), with a dialog when tokens push the
  /// pet into a higher form.
  void _maybeEvolve() {
    final pet = _pet;
    if (pet == null) return;
    final tokens = widget.state?.petTokensTotal ?? _tokensTotal;
    final index = petStageIndexForTokens(tokens);
    final seen = pet.stageSeen;
    if (seen == index) return;
    pet.stageSeen = index;
    unawaited(_store.save(pet));
    if (seen == null || seen > index) return;
    final species = petSpeciesById(pet.speciesId);
    final stage = species.stages[index];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('🎉 默契升级啦!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PetSprite(
                speciesId: 'dafeiyu',
                stageIndex: 0,
                animation: 'success',
              ),
              const SizedBox(height: 12),
              Text(
                '${pet.name} 和你成为了${stage.name}!',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('太好了'),
            ),
          ],
        ),
      );
    });
  }
}

/// First-run adoption card: name input + 领养 button.
class _AdoptView extends StatefulWidget {
  const _AdoptView({required this.onAdopt});

  final Future<void> Function(String name) onAdopt;

  @override
  State<_AdoptView> createState() => _AdoptViewState();
}

class _AdoptViewState extends State<_AdoptView> {
  final _controller = TextEditingController(text: '大肥鱼');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PetHabitatColors(Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.line),
            boxShadow: P.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PetSprite(speciesId: 'dafeiyu', stageIndex: 0, size: 220),
              const SizedBox(height: 12),
              const Text(
                '把大肥鱼接回家',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '最喜欢白米饭的大肥鱼，陪你一起工作。\n1M 上下文 = 1碗白米饭，自动吃饭、慢慢长大。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: '给它起个名字',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.lime,
                    foregroundColor: c.onLime,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    final name = _controller.text.trim();
                    if (name.isNotEmpty) widget.onAdopt(name);
                  },
                  child: const Text('领养'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trainer match dialog: a short matchmaking beat reveals a bot opponent
/// (nickname/rank/win-rate), then the pre-simulated [PetBattleResult] rounds
/// are revealed one at a time. Settling happens once per battle through
/// [onSettle].
class _BattleDialog extends StatefulWidget {
  const _BattleDialog({
    required this.pet,
    required this.tokens,
    required this.onSettle,
  });

  final Pet pet;
  final int tokens;

  /// Applies score and token-stake changes for the finished battle.
  final Future<void> Function(bool playerWon) onSettle;

  @override
  State<_BattleDialog> createState() => _BattleDialogState();
}

class _BattleDialogState extends State<_BattleDialog> {
  final _rng = math.Random();
  final _logScroll = ScrollController();

  late Pet _wild;
  late int _wildTokens;
  late PetBattleResult _result;
  late String _botNick;
  late PetRank _botRank;
  late int _botWinRate;
  bool _matching = true;
  int _dots = 0;
  int _revealed = 0;
  Timer? _timer;
  bool _settled = false;

  static const _matchDelay = Duration(milliseconds: 1400);
  static const _roundDelay = Duration(milliseconds: 650);

  @override
  void initState() {
    super.initState();
    _startBattle();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  void _startBattle() {
    final opponent = randomWildOpponent(petLevelForTokens(widget.tokens), _rng);
    _wild = opponent.pet;
    _wildTokens = opponent.tokens;
    _result = simulatePetBattle(
      player: widget.pet,
      playerTokens: widget.tokens,
      wild: _wild,
      wildTokens: _wildTokens,
      random: _rng,
    );
    // Bot persona: a trainer near the player's rank with a plausible record.
    _botNick = kPetBotNicknames[_rng.nextInt(kPetBotNicknames.length)];
    _botRank = petRankForScore(
      math.max(0, widget.pet.pkScore + _rng.nextInt(201) - 100),
    );
    _botWinRate = 40 + _rng.nextInt(26);
    _timer?.cancel();
    setState(() {
      _matching = true;
      _revealed = 0;
      _settled = false;
    });
    var elapsed = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      elapsed += 350;
      setState(() => _dots = (_dots + 1) % 3);
      if (elapsed >= _matchDelay.inMilliseconds) {
        timer.cancel();
        setState(() => _matching = false);
        _startRounds();
      }
    });
  }

  void _startRounds() {
    _timer = Timer.periodic(_roundDelay, (_) {
      if (!mounted) return;
      setState(() {
        _revealed++;
        _dots = (_dots + 1) % 4;
        if (_revealed >= _result.rounds.length) {
          _timer?.cancel();
          unawaited(_finish());
        }
      });
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _finish() async {
    if (_settled) return;
    _settled = true;
    await widget.onSettle(_result.playerWon);
  }

  @override
  Widget build(BuildContext context) {
    final done = !_matching && _revealed >= _result.rounds.length;
    final playerHp = _matching || _revealed == 0
        ? 100
        : _result.rounds[_revealed - 1].playerHp;
    final wildHp = _matching || _revealed == 0
        ? 100
        : _result.rounds[_revealed - 1].wildHp;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '训练家匹配赛',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _fighter(
                    speciesId: widget.pet.speciesId,
                    stageIndex: petStageIndexForTokens(widget.tokens),
                    mood: widget.pet.overall.round(),
                    name: widget.pet.name,
                    subtitle:
                        '${petRankForScore(widget.pet.pkScore).emoji} Lv.${petLevelForTokens(widget.tokens)}',
                    hp: playerHp,
                    color: P.accentLight,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('⚔️', style: TextStyle(fontSize: 24)),
                ),
                Expanded(
                  child: _matching
                      ? _fighter(
                          placeholder: true,
                          speciesId: _wild.speciesId,
                          stageIndex: petStageIndexForTokens(_wildTokens),
                          mood: _wild.overall.round(),
                          name: '匹配中…',
                          subtitle: '',
                          hp: 100,
                          color: P.danger,
                        )
                      : _fighter(
                          speciesId: _wild.speciesId,
                          stageIndex: petStageIndexForTokens(_wildTokens),
                          mood: _wild.overall.round(),
                          name:
                              '$_botNick的${_wild.name.replaceFirst('野生的', '')}',
                          subtitle:
                              '${_botRank.emoji}${_botRank.name} · 胜率$_botWinRate%',
                          hp: wildHp,
                          color: P.danger,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: _matching
                  ? Center(
                      child: Text(
                        '正在匹配训练家${'.' * (_dots + 1)}  ',
                        style: TextStyle(fontSize: 13, color: P.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScroll,
                      itemCount: _revealed,
                      itemBuilder: (_, i) => _logLine(_result.rounds[i]),
                    ),
            ),
            if (done) ...[
              const SizedBox(height: 10),
              Text(
                _result.playerWon
                    ? '🎉 赢了! +0.2M tokens,段位 +$kPetPkScoreWin'
                    : '💨 惜败… 被拿走 0.2M tokens,段位 $kPetPkScoreLose',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _result.playerWon ? P.success : P.danger,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('收工'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _startBattle,
                    child: const Text('再匹配一局'),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _matching ? '' : '战斗中…',
                  style: TextStyle(fontSize: 12, color: P.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fighter({
    required String speciesId,
    required int stageIndex,
    required int mood,
    required String name,
    required String subtitle,
    required int hp,
    required Color color,
    bool placeholder = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PetSprite(
          speciesId: speciesId,
          stageIndex: stageIndex,
          mood: mood,
          size: 72,
          animation: placeholder ? 'thinking' : 'idle',
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: P.textTertiary),
          ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: hp / 100,
            minHeight: 7,
            backgroundColor: P.fillMedium,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 2),
        Text('$hp/100', style: TextStyle(fontSize: 10, color: P.textTertiary)),
      ],
    );
  }

  Widget _logLine(BattleRound round) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Text(
        '${round.attackerIsPlayer ? '🗡️' : '🛡️'} ${round.attackerName} 造成 '
        '${round.damage} 点伤害${round.countered ? '(克制!)' : ''}',
        style: TextStyle(
          fontSize: 12,
          color: round.attackerIsPlayer ? null : P.textSecondary,
          fontWeight: round.countered ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

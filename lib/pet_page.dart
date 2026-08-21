/// Pet page: a local virtual pet (领养/喂食/玩耍/洗澡) rendered entirely from
/// [Pet] state; stats decay in real time via a periodic tick.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class _PetPageState extends State<PetPage> with TickerProviderStateMixin {
  final _store = PetStore();
  final _tokenStore = PetTokenStore();
  Pet? _pet;

  /// Persisted token total, used when no live [AppState] is attached.
  int _tokensTotal = 0;

  /// Null until the first load finishes (distinguishes "loading" from
  /// "no pet yet").
  bool _loaded = false;

  /// Breathing loop for the pet face.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// One-shot bounce when a care action lands.
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

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
    _breath.dispose();
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    widget.state?.ensurePetTokensLoaded();
    final pet = await _store.load();
    final tokens = await _tokenStore.total();
    if (!mounted) return;
    setState(() {
      _pet = pet;
      _tokensTotal = tokens;
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
  }

  Future<void> _mutate(void Function(Pet pet) action) async {
    final pet = _pet;
    if (pet == null) return;
    setState(() => action(pet));
    unawaited(_bounce.forward(from: 0));
    await _store.save(pet);
  }

  Future<void> _play() async {
    var refused = false;
    await _mutate((p) => refused = !p.play());
    if (refused && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('太饿啦,先喂点东西吧!')));
    }
  }

  Future<void> _adopt(String name) async {
    // Mystery egg: the species is drawn now but only reveals at hatching.
    final pet = Pet.newborn(name, DateTime.now().millisecondsSinceEpoch,
        speciesId: randomPetSpeciesId());
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
        title: const Text('给宠物改名'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的宠物'),
        actions: [
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
                        _maybeEvolve();
                        return _buildPetView(context, _pet!);
                      },
                    ),
    );
  }

  Widget _buildPetView(BuildContext context, Pet pet) {
    final tokens = widget.state?.petTokensTotal ?? _tokensTotal;
    final species = petSpeciesById(pet.speciesId);
    final stageIndex = petStageIndexForTokens(tokens);
    final stage = species.stages[stageIndex];
    final face = _hatchHint(tokens) ?? petFace(pet, stage);
    final days =
        (DateTime.now().millisecondsSinceEpoch - pet.bornAtMs) ~/
                Duration.millisecondsPerDay +
            1;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            gradient: P.brandGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [P.brandGlow],
          ),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_breath, _bounce]),
                builder: (context, child) {
                  final breath = 1 + 0.04 * _breath.value;
                  final bounce = 1 + 0.15 * (1 - _bounce.value) * _bounce.value * 4;
                  return Transform.scale(scale: breath * bounce, child: child);
                },
                child: Text(face, style: const TextStyle(fontSize: 96)),
              ),
              const SizedBox(height: 12),
              Text(pet.name,
                  style: TextStyle(
                      color: P.onAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(pet.statusLine,
                  style: TextStyle(
                      color: P.onAccent.withValues(alpha: 0.85), fontSize: 13)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _chip('${stage.name}期'),
                  // The species reveals itself once the egg hatches.
                  if (stageIndex > 0) ...[
                    const SizedBox(width: 8),
                    _chip(species.name),
                  ],
                  const SizedBox(width: 8),
                  _chip('相伴第 $days 天'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _growthCard(pet),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: '🍖',
                label: '喂食',
                onTap: () => _mutate((p) => p.feed()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: '⚽',
                label: '玩耍',
                onTap: _play,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: '🛁',
                label: '洗澡',
                onTap: () => _mutate((p) => p.clean()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: _openBattle,
            child: const Text('⚔️ 宠物对战 · 胜者赢取 0.2M tokens'),
          ),
        ),
      ],
    );
  }

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

  /// Settles the battle stake into the bonus pool and refreshes totals so
  /// the growth card (and any level-up evolution) react immediately.
  Future<void> _settleBattle(int delta) async {
    final total = await _tokenStore.addBonus(delta);
    await widget.state?.refreshPetTokens();
    if (mounted) setState(() => _tokensTotal = total);
  }

  /// Small pill on the hero card (stage name / days together).
  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: P.onAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(color: P.onAccent, fontSize: 12)),
      );

  /// The egg cracks open (🐣) during the last quarter-level before hatching
  /// into 幼崽; null for every other situation.
  String? _hatchHint(int tokens) {
    if (petStageIndexForTokens(tokens) != 0) return null;
    if (petLevelForTokens(tokens) + 1 < kPetStageMinLevels[1]) return null;
    return petLevelProgressForTokens(tokens) >= 0.75 ? '🐣' : null;
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
    // Hatching doubles as the species reveal for the mystery egg.
    final hatched = seen == 0 && index == 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(hatched ? '🎉 孵化啦!' : '🎉 进化啦!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(stage.base, style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 12),
              Text(
                hatched
                    ? '是一颗${species.name}蛋!${pet.name} 出生啦'
                    : '${pet.name} 进化成了 ${stage.name}!',
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

  /// Growth card: the level derives from cumulative cache-hit input tokens
  /// (1 M per level); the three care bars still read the pet's stats.
  Widget _growthCard(Pet pet) {
    final tokens = widget.state?.petTokensTotal ?? _tokensTotal;
    final level = petLevelForTokens(tokens);
    PetStage? nextStage;
    for (final candidate in petSpeciesById(pet.speciesId).stages) {
      if (candidate.minLevel > level) {
        nextStage = candidate;
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: P.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: P.fillLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('成长 Lv.$level',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('已命中 ${(tokens / kPetTokensPerLevel).toStringAsFixed(2)} M tokens',
                  style: TextStyle(fontSize: 12, color: P.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: petLevelProgressForTokens(tokens),
              minHeight: 8,
              backgroundColor: P.fillMedium,
              valueColor: AlwaysStoppedAnimation(P.accentLight),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('对话每命中 1M tokens 升一级',
                style: TextStyle(fontSize: 11, color: P.textTertiary)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              nextStage == null
                  ? '已是最终形态'
                  : 'Lv.${nextStage.minLevel} 进化为 ${nextStage.name} ${nextStage.base}',
              style: TextStyle(fontSize: 11, color: P.textTertiary),
            ),
          ),
          const SizedBox(height: 12),
          _StatBar(
              icon: '🍖', label: '饱腹', value: pet.hunger,
              color: const Color(0xFFFF9F43)),
          const SizedBox(height: 12),
          _StatBar(
              icon: '⚽', label: '心情', value: pet.mood,
              color: const Color(0xFFFF6B9D)),
          const SizedBox(height: 12),
          _StatBar(
              icon: '🛁', label: '清洁', value: pet.hygiene,
              color: const Color(0xFF54A0FF)),
        ],
      ),
    );
  }
}

/// One care-stat row: emoji icon, label, and a colored progress bar.
class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final String icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(label, style: TextStyle(fontSize: 13, color: P.textSecondary)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value / kPetStatMax,
              minHeight: 8,
              backgroundColor: P.fillMedium,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: P.textTertiary)),
        ),
      ],
    );
  }
}

/// Large tappable care-action button under the stats card.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: P.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: P.fillLight),
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// First-run adoption card: name input + 领养 button.
class _AdoptView extends StatefulWidget {
  const _AdoptView({required this.onAdopt});

  final Future<void> Function(String name) onAdopt;

  @override
  State<_AdoptView> createState() => _AdoptViewState();
}

class _AdoptViewState extends State<_AdoptView> {  final _controller = TextEditingController(text: '小哈');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: P.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: P.fillLight),
            boxShadow: P.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🥚', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 12),
              const Text('领养一颗神秘蛋',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('哈灵、雷光猫、苍月狼、焚天炎龙、九天凤凰……孵化那一刻才揭晓',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: P.textSecondary)),
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

/// Pet battle dialog: the battle is pre-simulated via [simulatePetBattle],
/// then the rounds are revealed one at a time over the HP bars and the log.
/// Settling happens once per battle through [onSettle].
class _BattleDialog extends StatefulWidget {
  const _BattleDialog({
    required this.pet,
    required this.tokens,
    required this.onSettle,
  });

  final Pet pet;
  final int tokens;

  /// Applies the stake delta (+/- [kPetBattleStake]) and refreshes totals.
  final Future<void> Function(int delta) onSettle;

  @override
  State<_BattleDialog> createState() => _BattleDialogState();
}

class _BattleDialogState extends State<_BattleDialog> {
  final _rng = math.Random();
  final _logScroll = ScrollController();

  late Pet _wild;
  late int _wildTokens;
  late PetBattleResult _result;
  int _revealed = 0;
  Timer? _timer;
  bool _settled = false;

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
    final opponent =
        randomWildOpponent(petLevelForTokens(widget.tokens), _rng);
    _wild = opponent.pet;
    _wildTokens = opponent.tokens;
    _result = simulatePetBattle(
      player: widget.pet,
      playerTokens: widget.tokens,
      wild: _wild,
      wildTokens: _wildTokens,
      random: _rng,
    );
    _timer?.cancel();
    setState(() {
      _revealed = 0;
      _settled = false;
    });
    _timer = Timer.periodic(_roundDelay, (_) {
      if (!mounted) return;
      setState(() {
        _revealed++;
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
    await widget
        .onSettle(_result.playerWon ? kPetBattleStake : -kPetBattleStake);
  }

  @override
  Widget build(BuildContext context) {
    final myStage =
        petSpeciesById(widget.pet.speciesId).stageForTokens(widget.tokens);
    final wildStage =
        petSpeciesById(_wild.speciesId).stageForTokens(_wildTokens);
    final done = _revealed >= _result.rounds.length;
    final playerHp =
        _revealed == 0 ? 100 : _result.rounds[_revealed - 1].playerHp;
    final wildHp = _revealed == 0 ? 100 : _result.rounds[_revealed - 1].wildHp;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('宠物对战',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _fighter(
                    face: petFace(widget.pet, myStage),
                    name: widget.pet.name,
                    level: petLevelForTokens(widget.tokens),
                    hp: playerHp,
                    color: P.accentLight,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('⚔️', style: TextStyle(fontSize: 24)),
                ),
                Expanded(
                  child: _fighter(
                    face: petFace(_wild, wildStage),
                    name: _wild.name,
                    level: petLevelForTokens(_wildTokens),
                    hp: wildHp,
                    color: P.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                controller: _logScroll,
                itemCount: _revealed,
                itemBuilder: (_, i) => _logLine(_result.rounds[i]),
              ),
            ),
            if (done) ...[
              const SizedBox(height: 10),
              Text(
                _result.playerWon
                    ? '🎉 赢了! +0.2M tokens'
                    : '💨 惜败… 被对方拿走了 0.2M tokens',
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
                    child: const Text('再来一局'),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('战斗中…',
                    style: TextStyle(fontSize: 12, color: P.textTertiary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fighter({
    required String face,
    required String name,
    required int level,
    required int hp,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(face, style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 4),
        Text('$name Lv.$level',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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

/// Stitch's Liquid Lime companion space, implemented with native widgets.
library;

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'src/theme.dart';
import 'src/pet.dart';

class PetHabitatColors {
  PetHabitatColors(this.dark);
  final bool dark;
  AppPalette get palette =>
      dark == P.isDark ? P : paletteFor(dark ? "obsidian" : "light");
  Color get bg => palette.bg;
  Color get surface => palette.card;
  Color get inset => palette.code;
  Color get text => palette.text;
  Color get muted => palette.textSecondary;
  Color get lime => palette.accent;
  Color get accent => palette.accent;
  Color get line => palette.divider;
  Color get onLime => palette.onAccent;
  List<BoxShadow> get shadows => palette.neuShadows;
}

class PetHabitat extends StatelessWidget {
  const PetHabitat({
    super.key,
    required this.pet,
    required this.contextTokens,
    required this.growthTokens,
    required this.activityLabel,
    required this.sprite,
    required this.onFeed,
    required this.onPlay,
    required this.onClean,
    required this.onBattle,
    required this.onAbout,
    required this.onRules,
  });
  final Pet pet;
  final int contextTokens;
  final int growthTokens;
  final String activityLabel;
  final Widget sprite;
  final VoidCallback onFeed, onPlay, onClean, onBattle, onAbout, onRules;

  @override
  Widget build(BuildContext context) {
    final c = PetHabitatColors(Theme.of(context).brightness == Brightness.dark);
    final days =
        ((DateTime.now().millisecondsSinceEpoch - pet.bornAtMs) ~/
                    Duration.millisecondsPerDay +
                1)
            .clamp(1, 999999);
    final level = petLevelForTokens(growthTokens);
    final stage = petSpeciesById(pet.speciesId).stageForTokens(growthTokens);
    return Stack(
      children: [
        Positioned(
          top: -130,
          right: -100,
          child: IgnorePointer(
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.lime.withValues(alpha: c.dark ? .07 : .15),
                    c.lime.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '我的陪伴搭子',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '今天也要好好吃饭',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(
                          c: c,
                          text: '相伴第 $days 天',
                          icon: Icons.favorite_outline_rounded,
                        ),
                        _Pill(c: c, text: stage.name),
                        _Pill(c: c, text: 'Lv.$level', accented: true),
                      ],
                    ),
                    SizedBox(height: 16),
                    _GlassSurface(
                      c: c,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, color: c.accent, size: 6),
                                SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    activityLabel,
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    pet.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            _Pill(c: c, text: '🍚 最喜欢白米饭啦！', accented: true),
                            SizedBox(
                              height: 208,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned(
                                    bottom: 8,
                                    child: Container(
                                      width: 180,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
                                        border: Border.all(
                                          color: c.accent.withValues(
                                            alpha: .24,
                                          ),
                                        ),
                                        color: c.lime.withValues(alpha: .04),
                                        boxShadow: [
                                          BoxShadow(
                                            color: c.lime.withValues(
                                              alpha: .08,
                                            ),
                                            blurRadius: 28,
                                            spreadRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  sprite,
                                ],
                              ),
                            ),
                            Text(
                              pet.statusLine,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.text, fontSize: 12),
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app_outlined,
                                  size: 13,
                                  color: c.muted,
                                ),
                                SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    '轻点摸头 · 长按提起',
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    _RiceCard(
                      c: c,
                      tokens: contextTokens,
                      onFeed: onFeed,
                      onRules: onRules,
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CareButton(
                            c: c,
                            icon: Icons.sports_esports_outlined,
                            label: '玩耍',
                            onTap: onPlay,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _CareButton(
                            c: c,
                            icon: Icons.shower_outlined,
                            label: '洗澡',
                            onTap: onClean,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    _CareStats(c: c, pet: pet),
                    SizedBox(height: 18),
                    _DetailRow(
                      c: c,
                      icon: Icons.auto_awesome_outlined,
                      title: '默契在慢慢长大',
                      subtitle: '成长 Lv.$level · ${stage.name}',
                      trailing: Padding(
                        padding: const EdgeInsets.all(4),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            value: petLevelProgressForTokens(growthTokens),
                            strokeWidth: 3,
                            color: c.accent,
                            backgroundColor: c.line,
                          ),
                        ),
                      ),
                      onTap: onRules,
                    ),
                    SizedBox(height: 10),
                    _DetailRow(
                      c: c,
                      icon: Icons.sports_martial_arts_rounded,
                      title: '训练家匹配赛',
                      subtitle:
                          '${petRankForScore(pet.pkScore).name} · ${pet.pkScore} 积分 · 训练奖励 0.2M',
                      onTap: onBattle,
                    ),
                    SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: onAbout,
                      icon: Icon(
                        Icons.favorite_outline,
                        size: 15,
                        color: c.muted,
                      ),
                      label: Text(
                        '大肥鱼 · 开源形象与动画',
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.c, required this.child});
  final PetHabitatColors c;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: P.neuShadow.withValues(alpha: c.dark ? .24 : .05),
          blurRadius: 20,
          offset: const Offset(6, 9),
        ),
        BoxShadow(
          color: P.glassHighlight.withValues(alpha: c.dark ? .025 : .75),
          blurRadius: 12,
          offset: const Offset(-4, -4),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: c.line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                c.dark ? P.glassHighlight.withValues(alpha: .08) : c.surface,
                c.surface.withValues(alpha: .78),
              ],
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.c,
    required this.text,
    this.icon,
    this.accented = false,
  });
  final PetHabitatColors c;
  final String text;
  final IconData? icon;
  final bool accented;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: c.inset.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: accented ? c.accent.withValues(alpha: .3) : c.line,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: accented ? c.accent : c.muted),
          SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: accented ? c.accent : c.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RiceCard extends StatelessWidget {
  const _RiceCard({
    required this.c,
    required this.tokens,
    required this.onFeed,
    required this.onRules,
  });
  final PetHabitatColors c;
  final int tokens;
  final VoidCallback onFeed, onRules;
  @override
  Widget build(BuildContext context) {
    final bowls = petRiceBowlsForTokens(tokens);
    final progress = petRiceBowlProgress(tokens);
    final remaining =
        (kPetTokensPerBowl - (tokens.clamp(0, 1 << 62) % kPetTokensPerBowl)) /
        kPetTokensPerBowl;
    // Round remaining context up so a tiny nonzero remainder never says zero.
    final remainingText = remaining < .01
        ? '不到 0.01'
        : ((remaining * 100).ceil() / 100).toStringAsFixed(2);
    return _GlassSurface(
      c: c,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.inset,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text('🍚', style: TextStyle(fontSize: 25)),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '大肥鱼的饭碗',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '1M 上下文 = 1碗白米饭',
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRules,
                  tooltip: '白米饭与成长规则',
                  icon: Icon(
                    Icons.info_outline_rounded,
                    color: c.muted,
                    size: 18,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.inset,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line.withValues(alpha: .65)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '已吃过 ',
                              style: TextStyle(fontSize: 13, color: c.muted),
                            ),
                            TextSpan(
                              text: '$bowls',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: c.text,
                                height: 1.2,
                              ),
                            ),
                            TextSpan(
                              text: ' 碗',
                              style: TextStyle(fontSize: 13, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '下一碗 ${(progress * 100).floor()}%',
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: c.lime,
                      backgroundColor: c.line,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '再累计 ${remainingText}M 上下文，就有下一碗',
                    style: TextStyle(color: c.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('feed-rice'),
              onPressed: onFeed,
              style: FilledButton.styleFrom(
                backgroundColor: c.lime,
                foregroundColor: c.onLime,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Text('🍚', style: TextStyle(fontSize: 22)),
              label: Text(
                '喂白米饭',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(height: 8),
            Text(
              '上下文累计自动吃饭 · 手动喂饭是互动',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareButton extends StatelessWidget {
  const _CareButton({
    required this.c,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final PetHabitatColors c;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: c.text,
      backgroundColor: c.surface,
      side: BorderSide(color: c.line),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    icon: Icon(icon, size: 19, color: c.accent),
    label: Text(label, style: const TextStyle(fontSize: 13)),
  );
}

class _CareStats extends StatelessWidget {
  const _CareStats({required this.c, required this.pet});
  final PetHabitatColors c;
  final Pet pet;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: c.inset,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: c.line),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final vertical =
            MediaQuery.textScalerOf(context).scale(12) > 16 ||
            constraints.maxWidth < 270;
        final stats = [
          (Icons.restaurant_rounded, '饱腹', pet.hunger),
          (Icons.sentiment_satisfied_alt, '心情', pet.mood),
          (Icons.water_drop_outlined, '清洁', pet.hygiene),
        ];
        final children = [
          for (final (icon, label, value) in stats)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: vertical ? 0 : 4,
                vertical: vertical ? 7 : 0,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: c.accent),
                      SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                      Spacer(),
                      Text(
                        '$value',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: value / kPetStatMax,
                      minHeight: 4,
                      color: c.accent,
                      backgroundColor: c.line,
                    ),
                  ),
                ],
              ),
            ),
        ];
        return vertical
            ? Column(children: children)
            : Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i != 0) const SizedBox(width: 12),
                    Expanded(child: children[i]),
                  ],
                ],
              );
      },
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.c,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final PetHabitatColors c;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Material(
    color: c.surface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Icon(icon, color: c.accent, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: c.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10),
            trailing ??
                Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
          ],
        ),
      ),
    ),
  );
}

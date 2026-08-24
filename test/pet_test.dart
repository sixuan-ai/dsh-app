/// Unit tests for the virtual-pet model: time decay, care actions,
/// token-driven growth, face priority, and JSON round-trip; plus a widget
/// smoke test of the page.
library;

import 'dart:math' as math;

import 'package:dsh_mobile/pet_page.dart';
import 'package:dsh_mobile/src/pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hour = Duration.millisecondsPerHour;

void main() {
  group('Pet model', () {
    test('newborn starts with full stats', () {
      final pet = Pet.newborn('小哈', 1000);
      expect(pet.hunger, kPetStatMax);
      expect(pet.mood, kPetStatMax);
      expect(pet.hygiene, kPetStatMax);
    });

    test('applyElapsed decays stats proportionally to elapsed hours', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(10 * hour);
      expect(pet.hunger, 100 - 10 * kPetHungerDecayPerHour);
      expect(pet.mood, 100 - 10 * kPetMoodDecayPerHour);
      expect(pet.hygiene, 100 - 10 * kPetHygieneDecayPerHour);
      expect(pet.lastTickMs, 10 * hour);
    });

    test('applyElapsed never raises stats or rewinds below zero', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(1000 * hour); // far future: clamps at 0
      expect(pet.hunger, 0);
      expect(pet.mood, 0);
      expect(pet.hygiene, 0);
      // Same or past timestamps are no-ops for stats.
      pet.feed();
      final hunger = pet.hunger;
      pet.applyElapsed(500 * hour);
      expect(pet.hunger, hunger);
    });

    test('feed restores hunger and clamps at max', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(5 * hour); // hunger 100-30=70
      pet.feed();
      expect(pet.hunger, 100);
    });

    test('play is refused when too hungry', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(20 * hour); // hunger 0-ish... exactly 100-120 → 0
      final mood = pet.mood;
      expect(pet.play(), isFalse);
      expect(pet.mood, mood);
    });

    test('play boosts mood at a hunger/hygiene cost', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(2 * hour); // hunger 88, mood 92, hygiene 94
      expect(pet.play(), isTrue);
      expect(pet.mood, 100); // 92+25 clamps
      expect(pet.hunger, 80);
      expect(pet.hygiene, 89);
    });

    test('clean restores hygiene', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(10 * hour); // hygiene 70
      pet.clean();
      expect(pet.hygiene, 100);
    });

    test('token totals drive level and progress (1 M per level)', () {
      expect(petLevelForTokens(0), 1);
      expect(petLevelProgressForTokens(0), 0);
      expect(petLevelForTokens(kPetTokensPerLevel + 400000), 2);
      expect(
        petLevelProgressForTokens(kPetTokensPerLevel + 400000),
        closeTo(0.4, 1e-9),
      );
      // Negative input is clamped, never a sub-1 level.
      expect(petLevelForTokens(-5), 1);
    });

    test('evolution stages map to level bands', () {
      final spirit = petSpeciesById('spirit');
      expect(spirit.stageForTokens(0).name, '灵蛋'); // Lv.1
      expect(spirit.stageForTokens(2 * kPetTokensPerLevel).name, '小哈仔'); // Lv.3
      expect(spirit.stageForTokens(5 * kPetTokensPerLevel).name, '哈灵猫'); // Lv.6
      expect(
        spirit.stageForTokens(9 * kPetTokensPerLevel).name,
        '威哈虎',
      ); // Lv.10
      expect(
        spirit.stageForTokens(14 * kPetTokensPerLevel).name,
        '哈灵龙皇',
      ); // Lv.15
      // Just below a boundary still belongs to the previous form.
      expect(spirit.stageForTokens(5 * kPetTokensPerLevel - 1).name, '小哈仔');
      expect(
        petStageIndexForTokens(14 * kPetTokensPerLevel),
        kPetStageMinLevels.length - 1,
      );
    });

    test('species registry: five mystery-egg chains, shared thresholds', () {
      expect(kPetSpecies.length, 5);
      for (final species in kPetSpecies) {
        expect(species.stages.length, kPetStageMinLevels.length);
        for (var i = 0; i < species.stages.length; i++) {
          expect(species.stages[i].minLevel, kPetStageMinLevels[i]);
        }
        // Every chain starts from the mystery egg.
        expect(species.stages.first.base, '🥚');
      }
      // Unknown/old ids fall back to the original chain.
      expect(petSpeciesById(null).id, 'spirit');
      expect(petSpeciesById('dinosaur').id, 'spirit');
      expect(petSpeciesById('dog').stages.last.name, '九尾天狐');
    });

    test('speciesId persists through JSON, old saves become spirit', () {
      final pet = Pet.newborn('小哈', 0, speciesId: 'dragon');
      expect(Pet.fromJson(pet.toJson(), 0).speciesId, 'dragon');
      expect(Pet.fromJson(const {'name': '豆豆'}, 0).speciesId, 'spirit');
    });

    test('rank ladder bands and pkScore persistence', () {
      expect(petRankForScore(0).name, '青铜');
      expect(petRankForScore(kPetPkScoreStart).name, '白银');
      expect(petRankForScore(1199).name, '白银');
      expect(petRankForScore(1200).name, '黄金');
      expect(petRankForScore(1400).name, '铂金');
      expect(petRankForScore(1600).name, '钻石');
      expect(petRankForScore(9999).name, '王者');
      // New pets start at 白银; the score round-trips through JSON.
      final pet = Pet.newborn('小哈', 0);
      expect(pet.pkScore, kPetPkScoreStart);
      pet.pkScore = 1234;
      expect(Pet.fromJson(pet.toJson(), 0).pkScore, 1234);
      // Old saves default to the starting score.
      expect(Pet.fromJson(const {'name': '豆豆'}, 0).pkScore, kPetPkScoreStart);
      // The bot nickname pool is usable.
      expect(kPetBotNicknames.length, greaterThanOrEqualTo(8));
      expect(kPetBotNicknames.every((n) => n.isNotEmpty), isTrue);
    });

    test('species counter wheel is cyclic in registry order', () {
      for (var i = 0; i < kPetSpecies.length; i++) {
        final attacker = kPetSpecies[i].id;
        final prey = kPetSpecies[(i + 1) % kPetSpecies.length].id;
        expect(
          petSpeciesCounters(attacker, prey),
          isTrue,
          reason: '$attacker counters $prey',
        );
        expect(petSpeciesCounters(prey, attacker), isFalse);
      }
      expect(petSpeciesCounters('unknown', 'spirit'), isFalse);
    });

    test('wild opponent stays near the player level with mid stats', () {
      final rng = math.Random(7);
      for (var i = 0; i < 20; i++) {
        final opponent = randomWildOpponent(6, rng);
        final level = petLevelForTokens(opponent.tokens);
        expect(level, inInclusiveRange(5, 7));
        expect(opponent.pet.name, startsWith('野生的'));
        expect(opponent.pet.hunger, inInclusiveRange(40, 90));
      }
    });

    test('battle simulation: a much stronger player wins, log is complete', () {
      final rng = math.Random(3);
      final player = Pet.newborn('小哈', 0, speciesId: 'spirit');
      final wild = Pet.newborn('野怪', 0, speciesId: 'dog')
        ..hunger = 40
        ..mood = 40
        ..hygiene = 40;
      final result = simulatePetBattle(
        player: player,
        playerTokens: 12 * kPetTokensPerLevel, // Lv.13
        wild: wild,
        wildTokens: 0, // Lv.1
        random: rng,
      );
      expect(result.playerWon, isTrue);
      expect(result.rounds, isNotEmpty);
      // Rounds alternate attackers and end with someone at 0 HP.
      for (var i = 1; i < result.rounds.length; i++) {
        expect(
          result.rounds[i].attackerIsPlayer,
          isNot(result.rounds[i - 1].attackerIsPlayer),
        );
      }
      expect(result.rounds.last.wildHp, 0);
      // spirit counters cat (next in wheel), and dog is two steps away:
      // no counter bonus against this opponent.
      expect(result.rounds.where((r) => r.countered), isEmpty);
    });

    test('battle simulation: counter wheel adds damage and wild can win', () {
      final rng = math.Random(11);
      // dragon counters phoenix; Lv.10 wild dragon vs Lv.1 player phoenix.
      final player = Pet.newborn('小哈', 0, speciesId: 'phoenix')
        ..hunger = 40
        ..mood = 40
        ..hygiene = 40;
      final wild = Pet.newborn('野生龙', 0, speciesId: 'dragon');
      final result = simulatePetBattle(
        player: player,
        playerTokens: 0,
        wild: wild,
        wildTokens: 9 * kPetTokensPerLevel, // Lv.10
        random: rng,
      );
      expect(result.playerWon, isFalse);
      expect(
        result.rounds.any((r) => r.countered && !r.attackerIsPlayer),
        isTrue,
      );
      expect(result.rounds.last.playerHp, 0);
    });
    test('rename trims and rejects blanks', () {
      final pet = Pet.newborn('小哈', 0);
      expect(pet.rename('   '), isFalse);
      expect(pet.name, '小哈');
      expect(pet.rename('  豆豆  '), isTrue);
      expect(pet.name, '豆豆');
    });

    test('face prioritizes the most urgent unmet need', () {
      const cat = PetStage(name: '小猫', minLevel: 6, base: '🐱');
      final pet = Pet.newborn('小哈', 0);
      expect(petFace(pet, cat), '😸'); // all full
      pet.hunger = 10;
      pet.hygiene = 5;
      expect(petFace(pet, cat), '😿'); // hunger checked first
      pet.hunger = 90;
      expect(petFace(pet, cat), '🙀'); // then hygiene
      pet.hygiene = 90;
      pet.mood = 5;
      expect(petFace(pet, cat), '😾'); // then mood
    });

    test('non-cat forms compose base emoji with mood marks', () {
      const tiger = PetStage(name: '猛虎', minLevel: 10, base: '🐯');
      final pet = Pet.newborn('小哈', 0);
      expect(petFace(pet, tiger), '🐯✨');
      pet.hunger = 10;
      expect(petFace(pet, tiger), '🐯💦');
      pet.hunger = 90;
      pet.hygiene = 10;
      expect(petFace(pet, tiger), '🐯🛁');
      pet.hygiene = 90;
      pet.mood = 10;
      expect(petFace(pet, tiger), '🐯💔');
      pet.mood = 90;
      expect(petFace(pet, tiger), '🐯✨');
      pet.hunger = 40;
      pet.mood = 40;
      pet.hygiene = 40;
      expect(petFace(pet, tiger), '🐯'); // ok band: plain base
      pet.hunger = 20;
      pet.mood = 20;
      pet.hygiene = 20;
      expect(petFace(pet, tiger), '🐯🌧️');
    });

    test('stageSeen round-trips through JSON, absent on old saves', () {
      final pet = Pet.newborn('小哈', 0)..stageSeen = 2;
      final restored = Pet.fromJson(pet.toJson(), 0);
      expect(restored.stageSeen, 2);
      expect(Pet.fromJson(const {'name': '豆豆'}, 0).stageSeen, isNull);
    });

    test('JSON round-trip preserves state', () {
      final pet = Pet.newborn('豆豆', 1234)
        ..feed()
        ..applyElapsed(1234 + 3 * hour);
      final restored = Pet.fromJson(pet.toJson(), 9999);
      expect(restored.name, pet.name);
      expect(restored.hunger, pet.hunger);
      expect(restored.mood, pet.mood);
      expect(restored.hygiene, pet.hygiene);
      expect(restored.bornAtMs, pet.bornAtMs);
      expect(restored.lastTickMs, pet.lastTickMs);
    });

    test('fromJson tolerates missing keys', () {
      final pet = Pet.fromJson(const {'name': '豆豆'}, 5000);
      expect(pet.name, '豆豆');
      expect(pet.hunger, kPetStatMax);
      expect(pet.bornAtMs, 5000);
    });

    test('fromJson ignores the retired v1.10.0 growth key', () {
      final pet = Pet.fromJson(const {'name': '豆豆', 'growth': 42}, 5000);
      expect(pet.name, '豆豆');
      expect(pet.toJson().containsKey('growth'), isFalse);
    });
  });

  group('PetStore', () {
    test('load returns null with no saved pet, then round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PetStore();
      expect(await store.load(), isNull);
      final pet = Pet.newborn('小哈', DateTime.now().millisecondsSinceEpoch);
      await store.save(pet);
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.name, '小哈');
      await store.save(null);
      expect(await store.load(), isNull);
    });
  });

  group('PetTokenStore', () {
    test('keeps the per-session max and sums across sessions', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PetTokenStore();
      expect(await store.total(), 0);
      expect(await store.record('s1', 1500000), 1500000);
      // A lower re-observation (e.g. replay from an older snapshot) loses.
      expect(await store.record('s1', 900000), 1500000);
      expect(await store.record('s2', 500000), 2000000);
      // A fresh instance reads the persisted map.
      expect(await PetTokenStore().total(), 2000000);
    });

    test('bonus pool joins the total and losses floor at zero', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PetTokenStore();
      await store.record('s1', 1000000);
      // Winning a battle adds the stake to the growth total.
      expect(await store.addBonus(kPetBattleStake), 1200000);
      expect(await PetTokenStore().total(), 1200000);
      // Losing drains the pool but never below zero, and never touches the
      // per-session observations.
      expect(await store.addBonus(-kPetBattleStake), 1000000);
      expect(await store.addBonus(-kPetBattleStake), 1000000);
      // record() still reports the grand total including the pool.
      await store.addBonus(kPetBattleStake);
      expect(await store.record('s2', 500000), 1700000);
    });
  });

  testWidgets('pet page adopts a pet and feeds it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Tall phone surface: the default 800x600 leaves the action row past the
    // ListView cache extent, so its elements never get built.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PetPage()));
    // The breathing loop never settles; advance on a real async zone instead.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    // Adoption view first.
    expect(find.text('领养'), findsOneWidget);
    await tester.tap(find.text('领养'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    // Pet view with stats and actions.
    expect(find.text('小哈'), findsWidgets);
    expect(find.text('相伴第 1 天'), findsOneWidget);
    expect(find.text('喂食'), findsOneWidget);
    expect(find.text('玩耍'), findsOneWidget);
    expect(find.text('洗澡'), findsOneWidget);
    await tester.tap(find.text('喂食'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('成长 Lv.1'), findsOneWidget);
  });
}

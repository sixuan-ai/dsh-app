/// Unit tests for the virtual-pet model: time decay, care actions, growth,
/// face priority, and JSON round-trip; plus a widget smoke test of the page.
library;

import 'package:dsh_mobile/pet_page.dart';
import 'package:dsh_mobile/src/pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hour = Duration.millisecondsPerHour;

void main() {
  group('Pet model', () {
    test('newborn starts with full stats and level 1', () {
      final pet = Pet.newborn('小哈', 1000);
      expect(pet.hunger, kPetStatMax);
      expect(pet.mood, kPetStatMax);
      expect(pet.hygiene, kPetStatMax);
      expect(pet.growth, 0);
      expect(pet.level, 1);
      expect(pet.levelProgress, 0);
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

    test('feed restores hunger, clamps at max, and grants growth', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(5 * hour); // hunger 100-30=70
      pet.feed();
      expect(pet.hunger, 100);
      expect(pet.growth, 5);
    });

    test('play is refused when too hungry', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(20 * hour); // hunger 0-ish... exactly 100-120 → 0
      final mood = pet.mood;
      expect(pet.play(), isFalse);
      expect(pet.mood, mood);
      expect(pet.growth, 0);
    });

    test('play boosts mood at a hunger/hygiene cost', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(2 * hour); // hunger 88, mood 92, hygiene 94
      expect(pet.play(), isTrue);
      expect(pet.mood, 100); // 92+25 clamps
      expect(pet.hunger, 80);
      expect(pet.hygiene, 89);
      expect(pet.growth, 6);
    });

    test('clean restores hygiene and grants growth', () {
      final pet = Pet.newborn('小哈', 0);
      pet.applyElapsed(10 * hour); // hygiene 70
      pet.clean();
      expect(pet.hygiene, 100);
      expect(pet.growth, 4);
    });

    test('growth drives level and progress', () {
      final pet = Pet.newborn('小哈', 0)
        ..growth = kPetGrowthPerLevel + 40;
      expect(pet.level, 2);
      expect(pet.levelProgress, closeTo(0.4, 1e-9));
    });

    test('rename trims and rejects blanks', () {
      final pet = Pet.newborn('小哈', 0);
      expect(pet.rename('   '), isFalse);
      expect(pet.name, '小哈');
      expect(pet.rename('  豆豆  '), isTrue);
      expect(pet.name, '豆豆');
    });

    test('face prioritizes the most urgent unmet need', () {
      final pet = Pet.newborn('小哈', 0);
      expect(pet.face, '😸'); // all full
      pet.hunger = 10;
      pet.hygiene = 5;
      expect(pet.face, '😿'); // hunger checked first
      pet.hunger = 90;
      expect(pet.face, '🙀'); // then hygiene
      pet.hygiene = 90;
      pet.mood = 5;
      expect(pet.face, '😾'); // then mood
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
      expect(restored.growth, pet.growth);
      expect(restored.bornAtMs, pet.bornAtMs);
      expect(restored.lastTickMs, pet.lastTickMs);
    });

    test('fromJson tolerates missing keys', () {
      final pet = Pet.fromJson(const {'name': '豆豆'}, 5000);
      expect(pet.name, '豆豆');
      expect(pet.hunger, kPetStatMax);
      expect(pet.bornAtMs, 5000);
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
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // Adoption view first.
    expect(find.text('领养'), findsOneWidget);
    await tester.tap(find.text('领养'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // Pet view with stats and actions.
    expect(find.text('小哈'), findsWidgets);
    expect(find.text('喂食'), findsOneWidget);
    expect(find.text('玩耍'), findsOneWidget);
    expect(find.text('洗澡'), findsOneWidget);
    await tester.tap(find.text('喂食'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('成长 Lv.1'), findsOneWidget);
  });
}

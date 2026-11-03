import 'package:dsh_mobile/pet_page.dart';
import 'package:dsh_mobile/src/pet.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'live context automatically feeds once; manual rice does not spend or duplicate context',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pet = Pet.newborn('米饭搭子', DateTime.now().millisecondsSinceEpoch)
        ..hunger = 10
        ..mood = 30
        ..riceBowlsSeen = 0;
      await PetStore().save(pet);
      final app = AppState();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: PetPage(state: app),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await PetTokenStore().record('session', 1000000);
        await app.refreshPetTokens();
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect((await PetStore().load())!.hunger, 40);
      expect(app.petContextTokensTotal, 1000000);
      final feed = find.byKey(const ValueKey('feed-rice'));
      await tester.ensureVisible(feed);
      await tester.tap(feed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect((await PetStore().load())!.hunger, 70);
      expect((await PetStore().load())!.riceBowlsSeen, 1);
      expect(await PetTokenStore().contextTotal(), 1000000);
      expect(await PetTokenStore().total(), 1000000);
      await tester.runAsync(() => app.refreshPetTokens());
      await tester.pumpAndSettle();
      expect((await PetStore().load())!.hunger, 70);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

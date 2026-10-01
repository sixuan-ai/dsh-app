import 'package:dsh_mobile/settings_center.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

Widget _page() => _wrap(
      SettingsCenterPage(
        language: LanguageController(),
        theme: ThemeController(),
        state: AppState(),
        socialBaseUrl: 'https://example.com/social',
        onConnectionCenter: () {},
        onCheckUpdate: () {},
        connectionGuideBuilder: (_) => const SizedBox(),
        changelogBuilder: (_) => const SizedBox(),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders language, theme, connection and help sections', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text(S.settings), findsWidgets);
    expect(find.text(S.language), findsOneWidget);
    expect(find.text(S.followSystem), findsOneWidget);
    expect(find.text(S.simplifiedChinese), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text(S.theme), findsOneWidget);
    expect(find.text(S.connectionCenter), findsOneWidget);
    expect(find.text(S.balanceTitle), findsOneWidget);
    expect(find.text(S.feedback), findsOneWidget);
    expect(find.text(S.support), findsOneWidget);
    expect(find.text(S.checkUpdate), findsOneWidget);
  });

  testWidgets('selecting a language updates the controller and UI', (
    tester,
  ) async {
    final controller = LanguageController();
    await tester.pumpWidget(
      _wrap(
        SettingsCenterPage(
          language: controller,
          theme: ThemeController(),
          state: AppState(),
          socialBaseUrl: 'https://example.com/social',
          onConnectionCenter: () {},
          onCheckUpdate: () {},
          connectionGuideBuilder: (_) => const SizedBox(),
          changelogBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(controller.languageId, 'en');
    // The app root re-assigns the global S on rebuild; in this isolated test
    // the controller state itself is the observable.
    expect(controller.s.settings, 'Settings');
  });

  testWidgets('developer tools stay hidden until developer mode is on', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text(S.developerSection), findsOneWidget);
    expect(find.text(S.developerMode), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text(S.developerMode),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(toggle.value, isFalse);
    expect(find.text(S.devTools), findsNothing);
  });

  testWidgets('enabling developer mode reveals and opens the tools', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(S.developerMode));
    await tester.tap(find.text(S.developerMode));
    await tester.pumpAndSettle();
    expect(find.text(S.devTools), findsOneWidget);

    await tester.ensureVisible(find.text(S.devTools));
    await tester.tap(find.text(S.devTools));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The tools page is on the navigator now (its restart control renders).
    expect(find.text(S.restartDsh), findsWidgets);

    // Disabling the switch hides the entry again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(S.developerMode));
    await tester.tap(find.text(S.developerMode));
    await tester.pumpAndSettle();
    expect(find.text(S.devTools), findsNothing);
  });

  testWidgets('developer mode persists across launches', (tester) async {
    SharedPreferences.setMockInitialValues({'devMode': true});
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text(S.devTools), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool('devMode'),
      isTrue,
    );
  });
}

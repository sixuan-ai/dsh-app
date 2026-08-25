/// On-device walkthrough of the developer-mode flow: real rendering, real
/// input events, a screenshot marker at every step, plus exact widget
/// coordinates (dumped as GEO lines) so an adb-driven session can replay the
/// same taps on the release build.
///
/// Each phase is its own testWidgets so the tree starts clean every time.
library;

import 'package:dsh_mobile/main.dart';
import 'package:dsh_mobile/settings_center.dart';
import 'package:dsh_mobile/session_drawer.dart';
import 'package:dsh_mobile/state.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void geo(String name, Offset center) {
    debugPrint(
      'GEO $name ${center.dx.toStringAsFixed(1)} ${center.dy.toStringAsFixed(1)}',
    );
  }

  /// Signals the external logcat watcher to grab a real framebuffer capture.
  Future<void> mark(String name) async {
    debugPrint('MARK $name');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  }

  testWidgets('phase 1: login page geometry', (tester) async {
    await tester.pumpWidget(const DshApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final fields = find.byType(TextField);
    geo('login_user', tester.getCenter(fields.first));
    geo('login_pass', tester.getCenter(fields.at(1)));
    geo('login_connect', tester.getCenter(find.text('连接')));
    await mark('01_login');
  });

  testWidgets('phase 2+3: drawer and more sheet geometry', (tester) async {
    final theme = ThemeController();
    final language = LanguageController();
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(theme.palette),
        home: Scaffold(
          body: const SizedBox.expand(),
          drawer: SessionDrawer(
            state: state,
            theme: theme,
            language: language,
            onLogout: () {},
            onNewSession: () {},
            onCheckUpdate: () {},
            onConnectionCenter: () {},
            connectionMode: 'public',
            localAvailable: true,
            updateAvailable: false,
            socialBaseUrl: 'https://dsh.ainotex.com/social',
            connectionGuideBuilder: (_) => const SizedBox(),
            changelogBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    debugPrint('GEO step drawer-open');
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    geo('drawer_more', tester.getCenter(find.text('更多功能')));
    await mark('02_drawer');

    await tester.tap(find.text('更多功能'));
    await tester.pumpAndSettle();
    debugPrint('GEO step sheet-open');
    geo('sheet_settings', tester.getCenter(find.text(S.settings)));
    await mark('03_more_sheet');
  });

  testWidgets('phase 4-7: settings developer-mode walkthrough', (tester) async {
    final theme = ThemeController();
    final language = LanguageController();
    final state = AppState();
    debugPrint('GEO step pump-settings');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(theme.palette),
        home: SettingsCenterPage(
          language: language,
          theme: theme,
          state: state,
          socialBaseUrl: 'https://dsh.ainotex.com/social',
          onConnectionCenter: () {},
          onCheckUpdate: () {},
          connectionGuideBuilder: (_) => const SizedBox(),
          changelogBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    debugPrint('GEO step settings-settling');
    await tester.pumpAndSettle();
    debugPrint('GEO step settings-settled');

    final scrollable = find.byType(Scrollable).first;
    final scroll = tester.state<ScrollableState>(scrollable).position;
    final before = scroll.pixels;
    // Gesture-driven scroll (Scrollable.ensureVisible's driven animation
    // stalls under the integration-test binding).
    await tester.scrollUntilVisible(
      find.text(S.developerMode),
      200,
      scrollable: scrollable,
    );
    debugPrint('GEO step scrolled');
    await tester.pumpAndSettle();
    debugPrint(
      'GEO settings_scroll ${((scroll.pixels - before)).toStringAsFixed(1)} ${scroll.pixels.toStringAsFixed(1)}',
    );
    geo('dev_switch', tester.getCenter(find.text(S.developerMode)));
    expect(
      find.text(S.devTools),
      findsNothing,
      reason: 'tools entry hidden while developer mode is off',
    );
    await mark('04_settings_dev_off');

    await tester.tap(find.text(S.developerMode));
    await tester.pumpAndSettle();
    expect(find.text(S.devTools), findsOneWidget);
    geo('dev_entry', tester.getCenter(find.text(S.devTools)));
    await mark('05_dev_mode_on');

    await tester.tap(find.text(S.devTools));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(S.restartDsh), findsWidgets);
    await mark('06_dev_tools');
    // NOTE: never taps the restart control.

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.developerMode));
    await tester.pumpAndSettle();
    expect(find.text(S.devTools), findsNothing);
    await mark('07_dev_mode_off_again');
  });
}

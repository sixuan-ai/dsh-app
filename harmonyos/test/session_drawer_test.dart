import 'package:dsh_mobile/session_drawer.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders connection and new session actions', (tester) async {
    final state = AppState();
    final theme = ThemeController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionDrawer(
            state: state,
            theme: theme,
            language: LanguageController(),
            onLogout: () {},
            onNewSession: () {},
            onCheckUpdate: () {},
            onConnectionCenter: () {},
            connectionMode: 'remote',
            localAvailable: false,
            updateAvailable: false,
            socialBaseUrl: 'https://example.com/social',
            connectionGuideBuilder: (_) => const SizedBox(),
            changelogBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('更多功能'), findsOneWidget);
  });

  testWidgets('selected session shows accent title and indicator', (
    tester,
  ) async {
    final state = AppState()
      ..sessions.add(
        SessionRow(
          sessionId: 's1',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: false,
          blank: false,
          title: '会话标题',
        ),
      )
      ..selectedSessionId = 's1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionDrawer(
            state: state,
            theme: ThemeController(),
            language: LanguageController(),
            onLogout: () {},
            onNewSession: () {},
            onCheckUpdate: () {},
            onConnectionCenter: () {},
            connectionMode: 'remote',
            localAvailable: false,
            updateAvailable: false,
            socialBaseUrl: 'https://example.com/social',
            connectionGuideBuilder: (_) => const SizedBox(),
            changelogBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(find.text('会话标题'));
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(title.style?.color, P.accentLight);
  });
}

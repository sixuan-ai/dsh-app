import 'package:dsh_mobile/session_drawer.dart';
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
}

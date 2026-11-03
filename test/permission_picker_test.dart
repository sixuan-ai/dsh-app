import 'package:dsh_mobile/composer.dart';
import 'package:dsh_mobile/session_drawer.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PermissionState extends AppState {
  PermissionState() {
    connectionStatus = ServerConnectionStatus.online;
    selectedSessionId = 's1';
    projections['s1'] = {
      'permissions': ProjectionCell({'currentValue': 'workspace-write'}, 1),
    };
  }
  final commands = <String>[];
  @override
  Future<List<Map<String, dynamic>>> listCommands() async => [
    {
      'name': 'permission',
      'description': '权限',
      'input': {'text': {}},
    },
    {
      'name': 'goal',
      'description': '目标',
      'input': {'text': {}},
    },
  ];
  @override
  Future<void> runCommand(String line) async {
    commands.add(line);
  }
}

Future<void> openComposerPicker(
  WidgetTester tester,
  PermissionState state,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Composer(state: state)),
    ),
  );
  await tester.tap(find.byTooltip('快捷命令'));
  await tester.pumpAndSettle();
  expect(find.text('/permission'), findsNothing);
  await tester.tap(find.text('权限模式'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'server permission shortcut opens choices without inserting a command',
    (tester) async {
      final state = PermissionState();
      addTearDown(state.dispose);
      await openComposerPicker(tester, state);
      expect(find.text('工作区写入'), findsOneWidget);
      expect(find.text('完全访问'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('工作区写入'));
      await tester.pumpAndSettle();
      expect(state.commands, ['/permission workspace-write']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('full access requires confirmation and cancel sends nothing', (
    tester,
  ) async {
    final state = PermissionState();
    addTearDown(state.dispose);
    await openComposerPicker(tester, state);
    await tester.tap(find.text('完全访问'));
    await tester.pumpAndSettle();
    expect(find.text(S.enableFullAccess), findsOneWidget);
    expect(state.commands, isEmpty);
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();
    expect(state.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drawer full access choice executes after confirmation', (
    tester,
  ) async {
    final state = PermissionState();
    addTearDown(state.dispose);
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
            socialBaseUrl: 'https://example.com',
            connectionGuideBuilder: (_) => const SizedBox(),
            changelogBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多功能'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(S.permissionMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.permissionMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完全访问'));
    await tester.pumpAndSettle();
    expect(state.commands, isEmpty);
    await tester.tap(find.text(S.enable));
    await tester.pumpAndSettle();
    expect(state.commands, ['/permission danger-full-access']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'switching sessions while confirming cannot change the new session permissions',
    (tester) async {
      final state = PermissionState();
      addTearDown(state.dispose);
      await openComposerPicker(tester, state);
      await tester.tap(find.text('完全访问'));
      await tester.pumpAndSettle();
      state.selectedSessionId = 'another';
      await tester.tap(find.text(S.enable));
      await tester.pumpAndSettle();
      expect(state.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

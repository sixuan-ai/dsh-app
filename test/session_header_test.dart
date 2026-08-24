import 'package:dsh_mobile/session_header.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title, subtitle, and new session action', (
    tester,
  ) async {
    final state = AppState();
    var newSessionCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: SessionHeader(
            state: state,
            title: '当前会话',
            subtitleParts: const ['DeepSeek', '正在生成…'],
            onModelPicker: () {},
            onNewSession: () => newSessionCalled = true,
            onRename: () {},
            onRefresh: () {},
            onCheckUpdate: () {},
            onLogout: () {},
          ),
        ),
      ),
    );

    expect(find.text('当前会话'), findsOneWidget);
    expect(find.text('DeepSeek · 正在生成…'), findsOneWidget);
    await tester.tap(find.byTooltip('新建会话'));
    expect(newSessionCalled, isTrue);
  });

  testWidgets('hides session-only actions without a selected session', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: SessionHeader(
            state: state,
            title: 'xHarness',
            subtitleParts: const [],
            onModelPicker: () {},
            onNewSession: () {},
            onRename: () {},
            onRefresh: () {},
            onCheckUpdate: () {},
            onLogout: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('切换模型'), findsNothing);
    expect(find.byTooltip('任务队列'), findsNothing);
  });

  testWidgets('tapping the title shows the full session name dialog', (
    tester,
  ) async {
    const longTitle = '这是一个非常长的会话标题，长到顶部栏肯定显示不下';
    final state = AppState()
      ..sessions.add(
        SessionRow(
          sessionId: 's1',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: false,
          blank: false,
          title: longTitle,
          cwd: '/home/x/work',
        ),
      )
      ..selectedSessionId = 's1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: SessionHeader(
            state: state,
            title: longTitle,
            subtitleParts: const [],
            onModelPicker: () {},
            onNewSession: () {},
            onRename: () {},
            onRefresh: () {},
            onCheckUpdate: () {},
            onLogout: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text(longTitle));
    await tester.pumpAndSettle();

    expect(find.text(S.sessionName), findsOneWidget);
    expect(find.text(longTitle), findsWidgets);
    expect(find.text('/home/x/work'), findsOneWidget);

    await tester.tap(find.text(S.confirm));
    await tester.pumpAndSettle();
    expect(find.text(S.sessionName), findsNothing);
  });
}

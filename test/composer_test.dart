/// Widget tests for the chat composer: the send button must survive typing —
/// a user report (v1.10.0, Xiaomi) had it vanish once text was entered.
library;

import 'package:dsh_mobile/main.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The IconButton carrying the send arrow (byTooltip matches RawTooltip).
  Finder sendButton() =>
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded);

  testWidgets('composer keeps and enables the send button after typing', (
    tester,
  ) async {
    final app = AppState();
    app.selectedSessionId = 's1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Composer(state: app)),
      ),
    );

    // Both buttons render before typing; send is disabled on an empty draft.
    expect(find.byTooltip('快捷命令'), findsOneWidget);
    expect(sendButton(), findsOneWidget);
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();

    // After typing, the send button is still in the tree and now enabled.
    expect(find.byTooltip('快捷命令'), findsOneWidget);
    expect(sendButton(), findsOneWidget);
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('login offers public and LAN connection modes', (tester) async {
    final app = AppState();
    await tester.pumpWidget(MaterialApp(home: ServerSetupPage(state: app)));
    expect(find.text('官网连接'), findsOneWidget);
    expect(find.text('局域网'), findsOneWidget);
    await tester.tap(find.text('局域网'));
    await tester.pump();
    expect(find.byIcon(Icons.lan_outlined), findsOneWidget);
    expect(find.textContaining('电脑地址'), findsOneWidget);
  });

  testWidgets('quick start sheet explains core actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickStartSheet()));
    expect(find.text('欢迎使用 xHarmess'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('处理确认'), findsOneWidget);
  });

  testWidgets('composer shows the stop button alongside send while running', (
    tester,
  ) async {
    final app = AppState();
    app.selectedSessionId = 's1';
    // A running session row surfaces the stop button next to send.
    app.sessions.add(
      SessionRow(sessionId: 's1', updatedAt: 0, running: true, blank: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Composer(state: app)),
      ),
    );
    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(sendButton(), findsOneWidget);
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNotNull);
  });
}

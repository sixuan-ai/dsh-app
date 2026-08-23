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
    expect(find.byTooltip('完全访问'), findsOneWidget);
    expect(sendButton(), findsOneWidget);
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();

    // After typing, the send button is still in the tree and now enabled.
    expect(find.byTooltip('快捷命令'), findsOneWidget);
    expect(find.byTooltip('完全访问'), findsOneWidget);
    expect(sendButton(), findsOneWidget);
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('login offers public and LAN connection modes', (tester) async {
    final app = AppState();
    await tester.pumpWidget(MaterialApp(home: ServerSetupPage(state: app)));
    expect(find.text('远程连接'), findsOneWidget);
    expect(find.text('本地连接'), findsOneWidget);
    await tester.tap(find.text('本地连接'));
    await tester.pump();
    expect(find.byIcon(Icons.lan_outlined), findsOneWidget);
    expect(find.textContaining('电脑地址'), findsOneWidget);
  });

  testWidgets('quick start sheet explains core actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickStartSheet()));
    expect(find.text('第一次使用？先看这四步'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('处理确认'), findsOneWidget);
  });

  testWidgets('tool images render as a conversation result above details', (
    tester,
  ) async {
    final app = AppState();
    final item =
        ChatItem.tool(
            id: 'tool-image',
            callId: 'c1',
            name: 'read_image',
            arguments: '{}',
          )
          ..completed = true
          ..resultText = '[图片]'
          ..images = [
            ChatImage(
              attachmentId: 'image-1',
              mediaType: 'image/png',
              name: 'test.png',
              data:
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
            ),
          ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: app, item: item),
        ),
      ),
    );
    expect(find.text('图片结果'), findsOneWidget);
    expect(find.text('来自 read_image'), findsOneWidget);
    expect(find.text('read_image'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
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

import 'package:dsh_mobile/chat_list.dart';
import 'package:dsh_mobile/chat_view.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders assistant markdown and interrupted status', (
    tester,
  ) async {
    final state = AppState();
    final item = ChatItem.assistant(
      id: 'a-1',
      blocks: [AssistantBlock('text', '**回答**')],
      interrupted: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: state, item: item),
        ),
      ),
    );

    expect(find.text('回答'), findsOneWidget);
    expect(find.text('已中断'), findsOneWidget);
  });

  testWidgets('renders retry action for error notice', (tester) async {
    final state = AppState();
    final item = ChatItem.notice(
      id: 'n-1',
      text: '执行失败',
      isError: true,
      retryText: '再试一次',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: state, item: item),
        ),
      ),
    );

    expect(find.text('执行失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('renders tool image before the tool detail card', (tester) async {
    final state = AppState();
    final item = ChatItem.tool(
      id: 't-1',
      callId: 'c-1',
      name: 'image_tool',
      arguments: '{}',
    )..images = [ChatImage(attachmentId: 'a-1', mediaType: 'image/png')];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: state, item: item),
        ),
      ),
    );

    expect(find.text('图片结果'), findsOneWidget);
    expect(find.text('image_tool'), findsWidgets);
  });

  testWidgets('running tool card pulses its status strip', (tester) async {
    final state = AppState();
    final item = ChatItem.tool(
      id: 't-1',
      callId: 'c-1',
      name: 'bash',
      arguments: '{}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: state, item: item),
        ),
      ),
    );
    expect(find.text('运行中'), findsOneWidget);
    // Pump a frame mid-animation without settling (the pulse loops forever).
    await tester.pump(const Duration(milliseconds: 450));

    item
      ..completed = true
      ..resultText = 'ok';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: state, item: item),
        ),
      ),
    );
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('reasoning card expands and collapses smoothly', (tester) async {
    final state = AppState();
    final item = ChatItem.assistant(
      id: 'a-1',
      blocks: [
        AssistantBlock('reasoning', '推理内容细节'),
        AssistantBlock('text', '正式回答'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatItemView(state: state, item: item),
        ),
      ),
    );
    // Completed messages start collapsed; streaming content stays hidden.
    expect(find.text('推理内容细节'), findsNothing);

    await tester.tap(find.text('思考过程'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('推理内容细节'), findsOneWidget);

    await tester.tap(find.text('思考过程'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('推理内容细节'), findsNothing);
  });

  testWidgets('shows empty and loading states in ChatList', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatList(state: state)),
      ),
    );
    expect(find.text('发送消息开始对话'), findsOneWidget);

    final loadingState = AppState()..loadingHistory = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatList(state: loadingState)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

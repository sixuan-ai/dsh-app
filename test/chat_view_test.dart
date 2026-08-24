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

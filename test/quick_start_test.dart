import 'package:dsh_mobile/quick_start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty session view exposes suggestions and new session', (
    tester,
  ) async {
    var newSession = false;
    String? suggestion;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptySessionView(
            onNewSession: () => newSession = true,
            onSuggestion: (value) => suggestion = value,
          ),
        ),
      ),
    );

    expect(find.text('开始一个新的对话'), findsOneWidget);
    await tester.tap(find.text('帮我 review 一段代码'));
    expect(suggestion, '帮我 review 一段代码');
    await tester.tap(find.widgetWithText(FilledButton, '新建会话'));
    expect(newSession, isTrue);
  });
}

import 'package:dsh_mobile/new_session_sheet.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with default workspace selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewSessionSheet(state: AppState())),
      ),
    );
    await tester.pump();
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('在默认工作区创建'), findsOneWidget);
    expect(find.text('创建'), findsOneWidget);
  });

  testWidgets('reveals custom directory input after selecting custom path', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewSessionSheet(state: AppState())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('在默认工作区创建'));
    await tester.pump();
    await tester.tap(find.text('自定义路径'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('必须是服务器上已存在的目录'), findsOneWidget);
  });
}

import 'package:dsh_mobile/login_view.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers remote and LAN connection modes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerSetupPage(
          state: AppState(),
          defaultServerUrl: 'https://example.com',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('远程连接'), findsOneWidget);
    expect(find.text('本地连接'), findsOneWidget);
    expect(find.text('example.com · 自动匹配你的实例'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
  });
}

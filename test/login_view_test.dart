import 'package:dsh_mobile/login_view.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers account login without network setup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerSetupPage(
          state: AppState(),
          defaultServerUrl: 'https://example.com',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('远程连接'), findsNothing);
    expect(find.text('本地连接'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('邮箱或用户名'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('password field toggles visibility', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerSetupPage(
          state: AppState(),
          defaultServerUrl: 'https://example.com',
        ),
      ),
    );
    await tester.pump();

    TextField passwordField() =>
        tester.widget<TextField>(find.widgetWithText(TextField, '密码'));
    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
    expect(passwordField().obscureText, isTrue);
  });
}

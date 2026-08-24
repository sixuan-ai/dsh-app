import 'package:dsh_mobile/connection_guide.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows remote setup steps by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ConnectionGuideSheet())),
    );
    expect(find.text('远程连接：让官网帮你找到电脑'), findsOneWidget);
    expect(find.text('申请远程连接服务'), findsOneWidget);
  });

  testWidgets('shows LAN safety and command steps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConnectionGuideSheet(initialMode: 'lan')),
      ),
    );
    expect(find.text('本地连接：手机直连电脑'), findsOneWidget);
    expect(
      find.text('dsh web --host 0.0.0.0 --port 3080 --no-open'),
      findsOneWidget,
    );
  });

  testWidgets('command blocks use the code surface with accent copy icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConnectionGuideSheet(initialMode: 'lan')),
      ),
    );
    await tester.pumpAndSettle();

    final copyIcon = tester.widget<Icon>(find.byIcon(Icons.copy).first);
    expect(copyIcon.color, P.accentLight);
  });
}

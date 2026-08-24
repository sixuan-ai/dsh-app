import 'package:dsh_mobile/changelog_view.dart';
import 'package:dsh_mobile/src/changelog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders current release and update summary', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChangelogPage()));
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('v$kAppVersion'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WhatsNewDialog())),
    );
    expect(find.text('v$kAppVersion 更新内容'), findsOneWidget);
    expect(find.text('查看全部'), findsOneWidget);
  });
}

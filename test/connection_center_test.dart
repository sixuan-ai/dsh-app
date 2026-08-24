import 'package:dsh_mobile/connection_center.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows active remote and unavailable local states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionCenterSheet(
            connectionMode: 'public',
            checkingLocal: false,
            localAvailable: false,
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () {},
          ),
        ),
      ),
    );

    expect(find.text('连接中心'), findsOneWidget);
    expect(find.text('当前正在使用'), findsOneWidget);
    expect(find.text('当前未检测到本地电脑'), findsOneWidget);
    expect(find.text('重新检测本地连接'), findsOneWidget);
  });

  testWidgets('active card uses the unified accent selection style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionCenterSheet(
            connectionMode: 'lan',
            checkingLocal: false,
            localAvailable: true,
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () {},
          ),
        ),
      ),
    );

    final activeTitle = tester.widget<Text>(find.text('本地连接'));
    expect(activeTitle.style?.color, P.accentLight);
    final inactiveTitle = tester.widget<Text>(find.text('远程连接'));
    expect(inactiveTitle.style?.color, isNull);
  });

  testWidgets('shows the direct Shenzhen card when wired', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionCenterSheet(
            connectionMode: 'direct',
            checkingLocal: false,
            localAvailable: false,
            onSwitchRemote: () {},
            onSwitchLocal: () {},
            onRefreshLocal: () {},
            onSwitchDirect: () {},
          ),
        ),
      ),
    );

    expect(find.text('深圳直连'), findsOneWidget);
    expect(find.text('当前正在使用'), findsOneWidget);
    final directTitle = tester.widget<Text>(find.text('深圳直连'));
    expect(directTitle.style?.color, P.accentLight);
  });
}

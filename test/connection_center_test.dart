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

    final activeTitle = tester.widgetList<Text>(find.text('本地电脑')).last;
    expect(activeTitle.style?.color, P.accentLight);
    final inactiveTitle = tester.widgetList<Text>(find.text('香港服务器')).last;
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

    expect(find.text('深圳服务器'), findsNWidgets(2));
    expect(find.text('当前连接'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('当前正在使用'), findsOneWidget);
    expect(find.text('正在使用'), findsOneWidget);
    expect(find.text('切换回香港服务器'), findsOneWidget);
    expect(find.text('切换到本地电脑'), findsOneWidget);
    expect(find.text('切换到深圳服务器'), findsNothing);
    final directTitle = tester.widgetList<Text>(find.text('深圳服务器')).last;
    expect(directTitle.style?.color, P.accentLight);
  });
}

import 'package:dsh_mobile/connection_center.dart';
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
}

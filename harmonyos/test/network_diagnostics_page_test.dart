import 'package:dsh_mobile/network_diagnostics_page.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports failures when the host is unreachable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NetworkDiagnosticsPage(state: AppState())),
    );
    expect(find.text('网络诊断'), findsOneWidget);
    // Eight samples spaced by 250ms; advance fake time past the whole run.
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('8 次探测失败（超时或连接错误）'), findsOneWidget);
    expect(find.text('重新检测'), findsOneWidget);
  });
}

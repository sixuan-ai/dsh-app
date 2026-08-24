import 'package:dsh_mobile/stats_bar.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides stats without a selected session', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatsBar(state: AppState())),
      ),
    );
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('tok/s'), findsNothing);
  });
}

import 'dart:convert';

import 'package:dsh_mobile/balance_page.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses the official balance response', () {
    final result = BalanceResult.fromJson({
      'is_available': true,
      'balance_infos': [
        {
          'currency': 'CNY',
          'total_balance': '110.00',
          'granted_balance': '10.00',
          'topped_up_balance': '100.00',
        },
      ],
    });
    expect(result.isAvailable, isTrue);
    expect(result.entries, hasLength(1));
    expect(result.entries.first.currency, 'CNY');
    expect(result.entries.first.total, '110.00');
    expect(result.entries.first.granted, '10.00');
    expect(result.entries.first.toppedUp, '100.00');
  });

  testWidgets('queries balance with the stored key and shows the card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'is_available': true,
          'balance_infos': [
            {
              'currency': 'CNY',
              'total_balance': '88.50',
              'granted_balance': '8.00',
              'topped_up_balance': '80.50',
            },
          ],
        }),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(home: BalancePage(client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sk-test-key');
    await tester.tap(find.text(S.balanceQuery));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.url.toString(), kDeepSeekBalanceUrl);
    expect(captured!.headers['Authorization'], 'Bearer sk-test-key');
    expect(find.text(S.balanceAvailable), findsOneWidget);
    expect(find.text('88.50'), findsOneWidget);
    expect(find.text(S.balanceGranted), findsOneWidget);
    expect(find.text('8.00'), findsOneWidget);
    expect(find.text('80.50'), findsOneWidget);
  });

  testWidgets('shows a clear error for an invalid key', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(
      (request) async => http.Response('unauthorized', 401),
    );
    await tester.pumpWidget(MaterialApp(home: BalancePage(client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sk-bad');
    await tester.tap(find.text(S.balanceQuery));
    await tester.pumpAndSettle();

    expect(find.text(S.balanceKeyInvalid), findsOneWidget);
  });

  testWidgets('empty key does not fire a request', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });
    await tester.pumpWidget(MaterialApp(home: BalancePage(client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.balanceQuery));
    await tester.pumpAndSettle();
    expect(called, isFalse);
  });
}

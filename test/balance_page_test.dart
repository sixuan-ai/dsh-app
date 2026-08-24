import 'dart:convert';

import 'package:dsh_mobile/balance_page.dart';
import 'package:dsh_mobile/main.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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

  testWidgets('queries the host gateway with Basic auth and shows the card', (
    tester,
  ) async {
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
    await tester.pumpWidget(
      MaterialApp(
        home: BalancePage(username: 'user', password: 'pass', client: client),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.balanceQuery));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.url.toString(), '$kDefaultServerUrl/api/balance');
    expect(captured!.headers['Authorization'], startsWith('Basic '));
    expect(find.text(S.balanceAvailable), findsOneWidget);
    expect(find.text('88.50'), findsOneWidget);
    expect(find.text(S.balanceGranted), findsOneWidget);
    expect(find.text('8.00'), findsOneWidget);
    expect(find.text('80.50'), findsOneWidget);
  });

  testWidgets('shows a clear error when the server has no key', (tester) async {
    final client = MockClient(
      (request) async =>
          http.Response(jsonEncode({'error': 'not configured'}), 503),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BalancePage(username: 'u', password: 'p', client: client),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.balanceQuery));
    await tester.pumpAndSettle();

    expect(find.text(S.balanceServerNoKey), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:dsh_mobile/feedback_page.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('renders the feedback form', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FeedbackPage(username: 'u', password: 'p'),
      ),
    );

    expect(find.text(S.feedbackTitle), findsOneWidget);
    expect(find.text(S.feedbackType), findsOneWidget);
    expect(find.text(S.describe), findsOneWidget);
    expect(find.text(S.submit), findsOneWidget);
    expect(find.text(S.typeBug), findsOneWidget);
  });

  testWidgets('submits content and pops on success', (tester) async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackPage(username: 'u', password: 'p', client: client),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '切换深圳后连接中心显示错误');
    await tester.tap(find.text(S.submit));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.url.path, '/social/feedback');
    expect(captured!.headers['Authorization'], startsWith('Basic '));
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['content'], '切换深圳后连接中心显示错误');
    expect(body['type'], 'bug');
  });

  testWidgets('empty description does not submit', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackPage(username: 'u', password: 'p', client: client),
      ),
    );

    await tester.tap(find.text(S.submit));
    await tester.pumpAndSettle();
    expect(called, isFalse);
  });
}

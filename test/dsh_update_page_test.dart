import 'dart:convert';

import 'package:dsh_mobile/dsh_update_page.dart';
import 'package:dsh_mobile/main.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses the update payload', () {
    final info = DshUpdateInfo.fromJson({
      'installed': '0.1.1-rc.2',
      'latest': '0.1.2',
      'hasUpdate': true,
      'notes': 'fix stuff',
      'releaseUrl': 'https://github.com/deepseek-ai/deepseek-harness/releases',
    });
    expect(info.installed, '0.1.1-rc.2');
    expect(info.latest, '0.1.2');
    expect(info.hasUpdate, isTrue);
    expect(info.notes, 'fix stuff');
  });

  testWidgets('shows up-to-date state when versions match', (tester) async {
    final client = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'installed': '0.1.1-rc.2',
            'latest': '0.1.1-rc.2',
            'hasUpdate': false,
            'notes': '',
            'releaseUrl': null,
          }),
        ),
        200,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DshUpdatePage(username: 'u', password: 'p', client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.dshUpToDate), findsOneWidget);
    expect(find.text('0.1.1-rc.2'), findsNWidgets(2)); // installed + latest
    expect(find.text(S.dshHowToUpdate), findsNothing);
  });

  testWidgets('shows update hint and notes when a release is newer', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'installed': '0.1.0',
            'latest': '0.1.1-rc.2',
            'hasUpdate': true,
            'notes': '* 修复若干问题',
            'releaseUrl': 'https://github.com/example',
          }),
        ),
        200,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DshUpdatePage(username: 'u', password: 'p', client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.dshUpdateAvailable), findsOneWidget);
    expect(find.text(S.dshHowToUpdate), findsOneWidget);
    expect(find.textContaining('npm install'), findsOneWidget);
    expect(find.text(S.dshReleaseNotes), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('queries the host gateway with Basic auth', (tester) async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'installed': '0.1.1-rc.2',
            'latest': '0.1.1-rc.2',
            'hasUpdate': false,
            'notes': '',
            'releaseUrl': null,
          }),
        ),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DshUpdatePage(username: 'u', password: 'p', client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.url.toString(), '$kDefaultServerUrl/api/dsh-update');
    expect(captured!.headers['Authorization'], startsWith('Basic '));
  });
}

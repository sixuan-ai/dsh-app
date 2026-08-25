import 'dart:convert';

import 'package:dsh_mobile/dev_tools_page.dart';
import 'package:dsh_mobile/main.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client _clientWith({
  Map<String, dynamic>? status,
  Map<String, dynamic>? logs,
  int statusCode = 200,
}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/api/dsh-status')) {
      return http.Response.bytes(
        utf8.encode(jsonEncode(status ?? {})),
        statusCode,
      );
    }
    if (request.url.path.endsWith('/api/dsh-logs')) {
      return http.Response.bytes(
        utf8.encode(jsonEncode(logs ?? {})),
        statusCode,
      );
    }
    return http.Response.bytes(utf8.encode('{}'), 200);
  });
}

void main() {
  testWidgets('renders running status chips and log sections', (tester) async {
    final client = _clientWith(
      status: {
        'version': '0.1.1-rc.2',
        'running': true,
        'pid': 7577,
        'uptime': '18:11:48',
        'rssKb': 1645328,
        'memPercent': 5.1,
        'cpuPercent': 2.3,
      },
      logs: {
        'proxy': '[auth] POST /api/host.describe -> pass',
        'dsh': 'dsh web: http://127.0.0.1:3080',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DevToolsPage(username: 'u', password: 'p', client: client),
      ),
    );
    // First refresh completes; the 3s auto timer stays pending otherwise.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(S.dshProcessRunning), findsOneWidget);
    expect(find.text('v0.1.1-rc.2'), findsOneWidget);
    expect(find.text(S.proxyLogs), findsOneWidget);
    expect(find.text(S.dshLogs), findsOneWidget);
    expect(find.textContaining('/api/host.describe'), findsOneWidget);
    expect(find.textContaining('127.0.0.1:3080'), findsOneWidget);
    expect(find.text(S.restartDsh), findsWidgets);
  });

  testWidgets('shows stopped state when the process is down', (tester) async {
    final client = _clientWith(
      status: {'version': '0.1.1-rc.2', 'running': false},
      logs: {'proxy': '', 'dsh': ''},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DevToolsPage(username: 'u', password: 'p', client: client),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(S.dshProcessStopped), findsOneWidget);
  });

  testWidgets('queries the gateway endpoints with Basic auth', (tester) async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(jsonEncode({'running': false, 'proxy': '', 'dsh': ''})),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DevToolsPage(username: 'u', password: 'p', client: client),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(captured, isNotNull);
    expect(
      captured!.url.toString().startsWith('$kDefaultServerUrl/api/dsh-'),
      isTrue,
    );
    expect(captured!.headers['Authorization'], startsWith('Basic '));
  });
}

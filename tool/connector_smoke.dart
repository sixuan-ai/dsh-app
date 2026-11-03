/// Read-only live check. Credentials are read from stdin, never argv or logs.
library;

import 'dart:convert';
import 'dart:io';
import 'package:dsh_mobile/src/protocol.dart';

Future<void> main() async {
  final config = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final ids = <Set<String>>[];
  for (final route in ['localUrl', 'remoteUrl']) {
    if (config[route] == null) continue;
    final api = DshApi(
      config[route] as String,
      username: config['username'] as String,
      password: config['password'] as String,
      certificateFingerprint: route == 'localUrl'
          ? config['fingerprint'] as String
          : null,
    );
    final watch = Stopwatch()..start();
    try {
      await api.hostReady().timeout(const Duration(seconds: 15));
      final value =
          await api
                  .call('session.list', {})
                  .timeout(const Duration(seconds: 15))
              as Map;
      final sessions = (value['items'] as List)
          .whereType<Map>()
          .map((r) => r['sessionId'] as String)
          .toSet();
      ids.add(sessions);
      stdout.writeln(
        jsonEncode({
          'route': route,
          'hostReady': true,
          'sessions': sessions.length,
          'elapsedMs': watch.elapsedMilliseconds,
        }),
      );
    } finally {
      api.close();
    }
  }
  if (ids.length == 2 &&
      (ids.first.difference(ids.last).isNotEmpty ||
          ids.last.difference(ids.first).isNotEmpty)) {
    throw StateError('LAN/public session identities differ');
  }
  stdout.writeln('PASS same desktop session snapshot across configured routes');
}

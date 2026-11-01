/// Read-only end-to-end check. Credentials arrive on stdin, never argv or logs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dsh_mobile/src/protocol.dart';

Future<void> main() async {
  final credentials =
      jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final login = await directoryLogin(
    kDefaultServerUrl,
    credentials['username'],
    credentials['password'],
  );
  stdout.writeln('directory: ${login.computers.length} computers');
  for (final c in login.computers) {
    final resolved = await directoryResolve(
      kDefaultServerUrl,
      username: credentials['username'],
      password: credentials['password'],
      computerId: c.id,
    );
    if (resolved.url != c.url) throw StateError('resolve mismatch');
    final api = DshApi(
      c.url,
      username: credentials['username'],
      password: credentials['password'],
    );
    try {
      final host = await api.hostReady().timeout(const Duration(seconds: 25));
      final sessions =
          await api
                  .call('session.list', {})
                  .timeout(const Duration(seconds: 25))
              as Map;
      stdout.writeln(
        '${c.id}: WebSocket ready; HTTP sessions=${(sessions['items'] as List).length}; host fields=${(host['host'] as Map).keys.join(',')}',
      );
    } finally {
      api.close();
    }
  }
}

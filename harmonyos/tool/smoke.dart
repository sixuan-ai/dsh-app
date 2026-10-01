/// CLI smoke test for the DSH web-API client against a live server.
/// Usage: dart run tool/smoke.dart [baseUrl] [username] [password]
library;

import 'dart:async';
import 'dart:io';

import 'package:dsh_mobile/src/protocol.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : 'http://127.0.0.1:3080';
  final api = DshApi(
    base,
    username: args.length > 1 ? args[1] : null,
    password: args.length > 2 ? args[2] : null,
  );
  var failures = 0;

  Future<void> check(String name, Future<void> Function() body) async {
    try {
      await body();
      stdout.writeln('PASS  $name');
    } catch (error) {
      failures++;
      stdout.writeln('FAIL  $name: $error');
    }
  }

  String? firstSessionId;

  await check('host.describe', () async {
    final value = await api.call('host.describe', {}) as Map<String, dynamic>;
    stdout.writeln('      version=${value['version']} provider=${value['provider']}/${value['model']}');
  });

  await check('session.list', () async {
    final value = await api.call('session.list', {}) as Map<String, dynamic>;
    final items = value['items'] as List;
    stdout.writeln('      ${items.length} session(s)');
    if (items.isNotEmpty) {
      firstSessionId = (items.first as Map)['sessionId'] as String;
    }
  });

  await check('session.history', () async {
    if (firstSessionId == null) {
      stdout.writeln('      skipped (no sessions)');
      return;
    }
    final value = await api.call('session.history', {
      'sessionId': firstSessionId,
      'maxMessages': 5,
    }) as Map<String, dynamic>;
    stdout.writeln('      ${(value['events'] as List).length} event(s), hasMore=${value['hasMore']}');
  });

  await check('events.host downlink', () async {
    // The host stream has no subscription baseline — it only speaks on
    // lifecycle changes. Success means the socket opens and stays quiet
    // without an error for a short window.
    Object? error;
    final sub = api.hostStream().listen(
      (frame) => stdout.writeln('      frame: ${frame.method}'),
      onError: (Object e) => error = e,
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    if (error != null) throw error!;
  });

  await check('events.mux downlink', () async {
    final completer = Completer<void>();
    final sub = api.muxStream().listen(
      (frame) {
        stdout.writeln('      frame: ${frame.method}');
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('mux stream closed without frames'));
        }
      },
    );
    await completer.future.timeout(const Duration(seconds: 10));
    await sub.cancel();
  });

  await check('create+prompt+cancel cycle', () async {
    final created = await api.call('session.create', {}) as Map<String, dynamic>;
    final sessionId = created['sessionId'] as String;
    stdout.writeln('      created $sessionId');
    final frames = <String>[];
    final sub = api.muxStream().listen((frame) {
      if (frame.payload['sessionId'] == sessionId) frames.add(frame.method);
    });
    await api.call('session.prompt', {
      'sessionId': sessionId,
      'mode': 'queue',
      'content': [
        {'type': 'text', 'text': '用一句话回答:1+1=?'}
      ],
      'clientTimeZone': 'Asia/Shanghai',
    });
    // Wait for the turn to start producing frames, then cancel to keep the smoke cheap.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline) &&
        !frames.any((f) => f == 'session/event')) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await api.call('session.cancel', {'sessionId': sessionId});
    await Future<void>.delayed(const Duration(seconds: 2));
    await sub.cancel();
    if (frames.isEmpty) throw StateError('no mux frames observed for the new session');
    stdout.writeln('      observed ${frames.length} frame(s): ${frames.take(6).join(', ')}');
  });

  api.close();
  stdout.writeln(failures == 0 ? '\nALL CHECKS PASSED' : '\n$failures CHECK(S) FAILED');
  exit(failures == 0 ? 0 : 1);
}

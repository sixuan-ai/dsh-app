import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/connector_transport.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String pin;
  late SecurityContext context;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('xharness-tls-test-');
    final key = '${dir.path}/key.pem', cert = '${dir.path}/cert.pem';
    final result = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'ec',
      '-pkeyopt',
      'ec_paramgen_curve:P-256',
      '-nodes',
      '-keyout',
      key,
      '-out',
      cert,
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
    ]);
    expect(result.exitCode, 0);
    final pem = await File(cert).readAsString();
    final der = base64Decode(
      pem.split('\n').where((l) => !l.startsWith('---')).join(),
    );
    pin = sha256.convert(der).toString();
    context = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    SecurityContext.defaultContext.setTrustedCertificates(cert);
  });
  tearDownAll(() => dir.delete(recursive: true));
  test(
    'pinned TLS rejects a trusted wrong certificate and a different authority',
    () async {
      final server = await HttpServer.bindSecure('127.0.0.1', 0, context);
      server.listen((req) {
        req.response.write('ok');
        req.response.close();
      });
      final origin = Uri.parse('https://127.0.0.1:${server.port}');
      final normal = connectorHttpClient(origin, null),
          good = connectorHttpClient(origin, pin),
          bad = connectorHttpClient(origin, '0' * 64);
      try {
        expect((await (await normal.getUrl(origin)).close()).statusCode, 200);
        expect((await (await good.getUrl(origin)).close()).statusCode, 200);
        await expectLater(
          bad.getUrl(origin),
          throwsA(isA<HandshakeException>()),
        );
        final other = connectorHttpClient(
          Uri.parse('https://localhost:${server.port}'),
          pin,
        );
        try {
          await expectLater(
            other.getUrl(origin),
            throwsA(isA<HandshakeException>()),
          );
        } finally {
          other.close(force: true);
        }
      } finally {
        normal.close(force: true);
        good.close(force: true);
        bad.close(force: true);
        await server.close(force: true);
      }
    },
  );
  test(
    'disconnect cancels a late paired host response without reviving the connection',
    () async {
      final server = await HttpServer.bindSecure('127.0.0.1', 0, context);
      final opened = Completer<void>();
      late WebSocket socket;
      late String streamId;
      server.listen((req) async {
        socket = await WebSocketTransformer.upgrade(req);
        socket.listen((data) {
          final message = jsonDecode(data as String) as Map;
          if (message['type'] == 'open') {
            streamId = message['streamId'] as String;
            if (!opened.isCompleted) opened.complete();
          }
        });
      });
      final origin = 'https://127.0.0.1:${server.port}';
      final state = AppState()
        ..pairedComputer = PairedComputer(
          nodeId: '12345678-1234-1234-1234-123456789abc',
          name: 'test',
          localUrl: origin,
          fingerprint: pin,
          username: 'device-test',
          password: 'test-only',
        );
      try {
        final pending = state.connect(
          origin,
          username: 'device-test',
          password: 'test-only',
        );
        await opened.future.timeout(const Duration(seconds: 4));
        state.disconnect();
        socket.add(
          jsonEncode({
            'type': 'item',
            'streamId': streamId,
            'value': {
              'type': 'ready',
              'host': {'home': '/tmp'},
            },
          }),
        );
        await pending.timeout(const Duration(seconds: 4));
        expect(state.connected, isFalse);
        expect(state.authUsername, isNull);
        expect(state.connectionStatus, ServerConnectionStatus.idle);
      } finally {
        state.dispose();
        if (opened.isCompleted) await socket.close();
        await server.close(force: true);
      }
    },
  );
}

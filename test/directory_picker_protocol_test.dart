import 'dart:convert';
import 'dart:io';

import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failure in [
    null,
    '404',
    'not found',
    'unavailable',
    'permission',
  ]) {
    test('directory picker flat args and legacy fallback: $failure', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, dynamic>>[];
      final subscription = server.listen((request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        received.add(body);
        final method = body['method'];
        if (method == 'directoryPicker/list' &&
            (failure == '404' || failure == 'not found')) {
          request.response.statusCode = failure == '404' ? 404 : 502;
          request.response.write('not found');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'result':
                  method == 'directoryPicker/list' &&
                      (failure == 'unavailable' || failure == 'permission')
                  ? {
                      'ok': false,
                      'error': {
                        'code': failure == 'unavailable'
                            ? 'directory-picker/unavailable'
                            : 'permission-denied',
                        'message': 'denied',
                      },
                    }
                  : {
                      'ok': true,
                      'value': method == 'directoryPicker/createDirectory'
                          ? '/home/x/new'
                          : {
                              'path': '/home/x',
                              'home': '/home/x',
                              'crumbs': [],
                              'entries': [],
                              'truncated': false,
                            },
                    },
            }),
          );
        }
        await request.response.close();
      });
      final state = AppState()
        ..attachApiForTest(
          DshApi('http://127.0.0.1:${server.port}'),
          startStreams: false,
        );
      try {
        if (failure == 'unavailable' || failure == 'permission') {
          await expectLater(state.listDirectory(), throwsA(isA<DshError>()));
          expect(received, hasLength(1));
        } else {
          expect((await state.listDirectory()).path, '/home/x');
          expect(received.first['payload']['args'], isEmpty);
          if (failure != null) {
            expect(received.map((body) => body['method']), [
              'directoryPicker/list',
              'host/listDirectory',
            ]);
          }
          received.clear();
          await state.listDirectory('/home/x');
          expect(received.first['payload']['args'], {'path': '/home/x'});
          expect(await state.createDirectory('/home/x', 'new'), '/home/x/new');
          expect(received.last['method'], 'directoryPicker/createDirectory');
          expect(received.last['payload']['args'], {
            'path': '/home/x',
            'name': 'new',
          });
        }
      } finally {
        state.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }
}

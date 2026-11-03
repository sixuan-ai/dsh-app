import 'dart:convert';
import 'dart:io';

import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'command catalog and permission execution use flat gateway args',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, dynamic>>[];
      final subscription = server.listen((request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        received.add(body);
        final args = body['payload']['args'] as Map;
        final list = body['method'] == 'commands/list';
        final valid = list
            ? args.length == 1 && args['agentId'] == 's1'
            : args.length == 3 &&
                  args['agentId'] == 's1' &&
                  args['line'] == '/permission danger-full-access' &&
                  args['submittedAttachments'] is List &&
                  (args['submittedAttachments'] as List).isEmpty;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'result': valid
                ? {
                    'ok': true,
                    'value': list
                        ? [
                            {
                              'name': 'permission',
                              'input': {'text': {}},
                            },
                          ]
                        : {
                            'commandId': 'cmd-1',
                            'result': {
                              'kind': 'success',
                              'text': 'preset danger-full-access',
                            },
                          },
                  }
                : {
                    'ok': false,
                    'error': {
                      'code': 'gateway/arguments-invalid',
                      'message': 'descriptor mismatch',
                    },
                  },
          }),
        );
        await request.response.close();
      });
      final api = DshApi('http://127.0.0.1:${server.port}');
      final state = AppState()
        ..attachApiForTest(api, startStreams: false)
        ..selectedSessionId = 's1';
      try {
        expect((await state.listCommands()).single['name'], 'permission');
        await state.runCommand('/permission danger-full-access');
        expect(received, hasLength(2));
        expect(received[1]['payload']['args'], {
          'agentId': 's1',
          'line': '/permission danger-full-access',
          'submittedAttachments': [],
        });
        expect(state.items.last.isError, isFalse);
        expect(state.items.last.pending, isFalse);
        expect(state.items.last.text, 'preset danger-full-access');
      } finally {
        state.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}

/// Unit tests for the session-event fold: history events and live mux frames
/// must produce the same conversation items the UI renders.
library;

import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> event(int seq, String type, Map<String, dynamic> data) => {
  'seq': seq,
  'time': 0,
  'type': type,
  'data': data,
};

void main() {
  group('session management state', () {
    test('pinning is local and toggles the pinned set', () async {
      final app = AppState();
      await app.setSessionPinned('s1', true);
      expect(app.pinnedSessionIds, contains('s1'));
      await app.setSessionPinned('s1', false);
      expect(app.pinnedSessionIds, isNot(contains('s1')));
    });
  });

  group('event fold', () {
    test('user image references are preserved for authenticated loading', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'user/message', {
          'source': {'kind': 'user'},
          'content': [
            {'type': 'text', 'text': '看图'},
            {
              'type': 'image',
              'attachment': {
                'attachmentId': 'img-1',
                'mediaType': 'image/jpeg',
                'bytes': 1234,
                'width': 640,
                'height': 480,
                'name': 'photo.jpg',
              },
            },
          ],
        }),
      );
      expect(app.items.single.text, '看图');
      expect(app.items.single.images, hasLength(1));
      expect(app.items.single.images.single.attachmentId, 'img-1');
      expect(app.items.single.images.single.width, 640);
    });

    test(
      'assistant image references are preserved for authenticated loading',
      () {
        final app = AppState();
        app.foldForTest(
          event(1, 'assistant/message', {
            'turn': 1,
            'step': 1,
            'message': {
              'content': [
                {'type': 'text', 'text': '生成完成'},
                {
                  'type': 'image',
                  'attachment': {
                    'attachmentId': 'generated-1',
                    'mediaType': 'image/png',
                    'bytes': 2048,
                    'width': 1200,
                    'height': 800,
                    'name': 'poster.png',
                  },
                },
              ],
            },
          }),
        );
        expect(app.items.single.kind, ChatItemKind.assistant);
        expect(app.items.single.blocks.single.text, '生成完成');
        expect(app.items.single.images.single.attachmentId, 'generated-1');
        expect(app.items.single.images.single.mediaType, 'image/png');
      },
    );

    test('user message with user source renders a user bubble', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'user/message', {
          'id': 'm1',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '你好'},
          ],
          'source': {'kind': 'user', 'rpcId': 'r1'},
        }),
      );
      expect(app.items, hasLength(1));
      expect(app.items.single.kind, ChatItemKind.user);
      expect(app.items.single.text, '你好');
    });

    test('plugin-injected user messages stay off the surface', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'user/message', {
          'id': 'm1',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'context'},
          ],
          'source': {'kind': 'plugin', 'plugin': 'x'},
        }),
      );
      expect(app.items, isEmpty);
    });

    test('chunks accumulate and the final message replaces the stream', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': '你好'},
        }),
      );
      app.foldForTest(
        event(2, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': '，世界'},
        }),
      );
      expect(app.items, hasLength(1));
      expect(app.items.single.blocks.single.text, '你好，世界');
      expect(app.selectedStreaming, isTrue);

      app.foldForTest(
        event(3, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': {
            'id': 'a1',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': '你好，世界'},
            ],
            'source': {'kind': 'model'},
          },
        }),
      );
      expect(app.items, hasLength(1));
      expect(app.items.single.kind, ChatItemKind.assistant);
      expect(app.items.single.blocks.single.text, '你好，世界');
      expect(app.selectedStreaming, isFalse);
    });

    test('tool call pairs with its result by callId', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'tool/call', {
          'turn': 1,
          'step': 1,
          'callId': 'c1',
          'name': 'bash',
          'arguments': '{"command":"ls"}',
        }),
      );
      app.foldForTest(
        event(2, 'tool/result', {
          'turn': 1,
          'step': 1,
          'message': {
            'id': 'r1',
            'role': 'user',
            'content': [
              {
                'type': 'tool-result',
                'toolCallId': 'c1',
                'content': [
                  {'type': 'text', 'text': 'file.txt'},
                ],
              },
            ],
            'source': {'kind': 'tool'},
          },
        }),
      );
      expect(app.items, hasLength(1));
      final tool = app.items.single;
      expect(tool.kind, ChatItemKind.tool);
      expect(tool.name, 'bash');
      expect(tool.completed, isTrue);
      expect(tool.resultText, 'file.txt');
      expect(tool.resultIsError, isFalse);
    });

    test('duplicate replays at or below the watermark are dropped', () {
      final app = AppState();
      app.foldForTest(
        event(5, 'user/message', {
          'id': 'm1',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hi'},
          ],
          'source': {'kind': 'user'},
        }),
      );
      app.foldForTest(
        event(5, 'user/message', {
          'id': 'm1',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hi'},
          ],
          'source': {'kind': 'user'},
        }),
      );
      expect(app.items, hasLength(1));
    });

    test('folded items inherit the event timestamp', () {
      final app = AppState();
      app.foldForTest({
        'seq': 1,
        'time': 1756000000000,
        'type': 'user/message',
        'data': {
          'id': 'm1',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hi'},
          ],
          'source': {'kind': 'user'},
        },
      });
      expect(app.items.single.time, 1756000000000);
    });
  });

  group('command lifecycle', () {
    test(
      'command/run renders echo plus pending status; command/done settles it',
      () {
        final app = AppState();
        app.foldForTest(
          event(1, 'command/run', {
            'commandId': 'c1',
            'name': 'compact',
            'source': {'kind': 'user'},
          }),
        );
        expect(app.items, hasLength(2));
        expect(app.items[0].kind, ChatItemKind.user);
        expect(app.items[0].text, '/compact');
        expect(app.items[1].kind, ChatItemKind.notice);
        expect(app.items[1].pending, isTrue);

        app.foldForTest(
          event(2, 'command/done', {
            'commandId': 'c1',
            'kind': 'success',
            'text': '已压缩 12 条消息',
          }),
        );
        expect(app.items, hasLength(2));
        expect(app.items[1].pending, isFalse);
        expect(app.items[1].text, '已压缩 12 条消息');
        expect(app.items[1].isError, isFalse);
      },
    );

    test('command/run with args reconstructs the typed line', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'command/run', {
          'commandId': 'c2',
          'name': 'goal',
          'args': ' 写一个应用',
          'source': {'kind': 'user'},
        }),
      );
      expect(app.items[0].text, '/goal 写一个应用');
    });

    test(
      'a composer-sent command is adopted by command/run, not duplicated',
      () {
        final app = AppState();
        app.beginLocalCommand('/compact');
        expect(app.items, hasLength(2));
        expect(app.items[1].pending, isTrue);

        app.foldForTest(
          event(1, 'command/run', {
            'commandId': 'c1',
            'name': 'compact',
            'source': {'kind': 'user'},
          }),
        );
        expect(app.items, hasLength(2));
        expect(app.items[0].id, 'cmdin-c1');
        expect(app.items[1].id, 'cmdrun-c1');
        expect(app.items[1].pending, isTrue);

        app.foldForTest(
          event(2, 'command/done', {
            'commandId': 'c1',
            'kind': 'error',
            'text': '当前正在进行压缩任务',
          }),
        );
        expect(app.items, hasLength(2));
        expect(app.items[1].pending, isFalse);
        expect(app.items[1].isError, isTrue);
        expect(app.items[1].text, '当前正在进行压缩任务');
      },
    );

    test('adoption matches recordInput-less commands by name prefix', () {
      final app = AppState();
      app.beginLocalCommand('/feedback 很好用的应用');
      // /feedback sets recordInput:false, so the event carries no args.
      app.foldForTest(
        event(1, 'command/run', {
          'commandId': 'c3',
          'name': 'feedback',
          'source': {'kind': 'user'},
        }),
      );
      expect(app.items, hasLength(2));
      expect(app.items[0].id, 'cmdin-c3');
      expect(app.items[0].text, '/feedback 很好用的应用');
    });

    test('command/done without a seen run renders a keyed standalone row', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'command/done', {
          'commandId': 'c9',
          'kind': 'success',
          'text': '完成',
        }),
      );
      expect(app.items.single.id, 'cmddone-c9');
      expect(app.items.single.pending, isFalse);
    });

    test('a duplicate command/run does not duplicate the rows', () {
      final app = AppState();
      app.foldForTest(
        event(1, 'command/run', {
          'commandId': 'c1',
          'name': 'compact',
          'source': {'kind': 'user'},
        }),
      );
      app.foldForTest(
        event(2, 'command/run', {
          'commandId': 'c1',
          'name': 'compact',
          'source': {'kind': 'user'},
        }),
      );
      expect(app.items, hasLength(2));
    });
  });

  group('chat item cache serialization', () {
    test('assistant item survives a json roundtrip', () {
      final item = ChatItem.assistant(
        id: 'a-1',
        blocks: [AssistantBlock('reasoning', '想'), AssistantBlock('text', '答')],
        usage: const {'totalTokens': 42},
        interrupted: true,
      );
      final restored = chatItemFromJson(chatItemToJson(item));
      expect(restored.kind, ChatItemKind.assistant);
      expect(restored.id, 'a-1');
      expect(restored.blocks.map((b) => b.type), ['reasoning', 'text']);
      expect(restored.blocks.map((b) => b.text), ['想', '答']);
      expect(restored.usage, {'totalTokens': 42});
      expect(restored.interrupted, isTrue);
    });

    test('tool item survives a json roundtrip', () {
      final item =
          ChatItem.tool(
              id: 't-1',
              callId: 'c1',
              name: 'bash',
              arguments: '{"command":"ls"}',
            )
            ..resultText = 'file.txt'
            ..resultIsError = true
            ..completed = true;
      final restored = chatItemFromJson(chatItemToJson(item));
      expect(restored.kind, ChatItemKind.tool);
      expect(restored.callId, 'c1');
      expect(restored.name, 'bash');
      expect(restored.arguments, '{"command":"ls"}');
      expect(restored.resultText, 'file.txt');
      expect(restored.resultIsError, isTrue);
      expect(restored.completed, isTrue);
    });

    test('oversized text fields are capped for storage', () {
      final item = ChatItem.user(id: 'u-1', text: 'x' * 9000);
      final restored = chatItemFromJson(chatItemToJson(item));
      expect(restored.text.length, 8000);
    });
  });

  group('user level', () {
    test('thresholds map counts to levels', () {
      expect(userLevelFor(0).level, 1);
      expect(userLevelFor(4).level, 1);
      expect(userLevelFor(5).level, 2);
      expect(userLevelFor(99).level, 5);
      expect(userLevelFor(100).level, 6);
      expect(userLevelFor(10000).level, levelThresholds.length);
    });

    test('progress and remaining track the next threshold', () {
      final level = userLevelFor(20); // Lv.3 [15, 30)
      expect(level.level, 3);
      expect(level.remaining, 10);
      expect(level.progress, closeTo((20 - 15) / (30 - 15), 1e-9));
      final maxed = userLevelFor(10000);
      expect(maxed.next, isNull);
      expect(maxed.progress, 1);
      expect(maxed.remaining, 0);
    });
  });
}

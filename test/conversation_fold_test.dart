import 'package:dsh_mobile/src/conversation.dart';
import 'package:dsh_mobile/src/conversation_fold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('folds streaming assistant deltas into indexed blocks', () {
    final target = <ChatItem>[];
    final streams = <String, ChatItem>{};
    final result = foldCoreConversationEvent(
      type: 'assistant/chunk',
      data: {
        'turn': 1,
        'step': 2,
        'chunk': {'type': 'text-delta', 'index': 0, 'text': '你好'},
      },
      seq: 3,
      target: target,
      live: true,
      eventTime: 10,
      streams: streams,
      toolItems: {},
      pendingPrompts: {},
    );
    foldCoreConversationEvent(
      type: 'assistant/chunk',
      data: {
        'turn': 1,
        'step': 2,
        'chunk': {'type': 'text-delta', 'index': 0, 'text': '世界'},
      },
      seq: 4,
      target: target,
      live: true,
      eventTime: 11,
      streams: streams,
      toolItems: {},
      pendingPrompts: {},
    );

    expect(result, ConversationFoldResult.handled);
    expect(target.single.blocks.single.text, '你好世界');
  });

  test('pairs tool result with an earlier call', () {
    final target = <ChatItem>[];
    final streams = <String, ChatItem>{};
    final toolItems = <String, ChatItem>{};
    final pendingPrompts = <String, ChatItem>{};
    foldCoreConversationEvent(
      type: 'tool/call',
      data: {'callId': 'c1', 'name': 'read', 'arguments': '{}'},
      seq: 1,
      target: target,
      live: true,
      eventTime: null,
      streams: streams,
      toolItems: toolItems,
      pendingPrompts: pendingPrompts,
    );
    foldCoreConversationEvent(
      type: 'tool/result',
      data: {
        'message': {
          'content': [
            {
              'toolCallId': 'c1',
              'content': [
                {'type': 'text', 'text': '完成'},
              ],
            },
          ],
        },
      },
      seq: 2,
      target: target,
      live: true,
      eventTime: null,
      streams: streams,
      toolItems: toolItems,
      pendingPrompts: pendingPrompts,
    );

    expect(target, hasLength(1));
    expect(target.single.resultText, '完成');
    expect(target.single.completed, isTrue);
  });
}

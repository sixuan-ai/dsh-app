import 'package:dsh_mobile/chat_list.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tail revision changes only with rendered tail content', () {
    final first = ChatItem.assistant(
      id: 'stream-1',
      blocks: [AssistantBlock('text', 'hello')],
    );
    final items = [first];
    final initial = chatTailRevision(items);

    first.blocks.first.text = 'hello world';
    expect(chatTailRevision(items), isNot(initial));

    final afterChunk = chatTailRevision(items);
    final unrelated = ChatItem.notice(id: 'older', text: 'unrelated');
    expect(chatTailRevision([unrelated, first]), afterChunk);
  });

  test('tail revision captures tool completion without list growth', () {
    final tool = ChatItem.tool(
      id: 'tool-1',
      callId: 'call-1',
      name: 'bash',
      arguments: '{}',
    );
    final initial = chatTailRevision([tool]);
    tool
      ..resultText = 'done'
      ..completed = true;
    expect(chatTailRevision([tool]), isNot(initial));
  });
}

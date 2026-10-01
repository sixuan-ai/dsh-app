import 'package:dsh_mobile/home_view.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('header selection ignores unrelated streaming item content', () {
    final state = AppState();
    final before = HomeHeaderSelection.from(state);
    state.items.add(
      ChatItem.assistant(
        id: 'stream-1',
        blocks: [AssistantBlock('text', 'hello')],
      ),
    );
    state.items.last.blocks.first.text = 'hello world';
    expect(HomeHeaderSelection.from(state), before);
  });

  test('composer selection includes server availability', () {
    expect(
      const ComposerSelection('session-1', true, true),
      const ComposerSelection('session-1', true, true),
    );
    expect(
      const ComposerSelection('session-1', true, true),
      isNot(const ComposerSelection('session-1', false, true)),
    );
    expect(
      const ComposerSelection('session-1', true, true),
      isNot(const ComposerSelection('session-1', true, false)),
    );
  });
}

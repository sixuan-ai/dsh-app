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

  test('composer selection compares only session and running state', () {
    expect(
      const ComposerSelection('session-1', true),
      const ComposerSelection('session-1', true),
    );
    expect(
      const ComposerSelection('session-1', true),
      isNot(const ComposerSelection('session-1', false)),
    );
  });
}

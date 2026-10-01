import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identifies subagent sessions from origin metadata', () {
    expect(isSubagentSessionPayload({'origin': 'subagent'}), isTrue);
    expect(
      isSubagentSessionPayload({
        'projections': {
          'values': {
            'subagent': {'mode': 'continuable'},
          },
        },
      }),
      isTrue,
    );
    expect(isSubagentSessionPayload({'origin': 'user'}), isFalse);
  });
}

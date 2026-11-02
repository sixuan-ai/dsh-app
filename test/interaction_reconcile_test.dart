/// Regression tests for pending-interaction reconciliation.
///
/// The gateway pushes a `cancel` frame to every client that still holds a
/// waterfall event, but a client that was disconnected at that moment never
/// learns about the resolution. On reconnect the gateway re-delivers only the
/// still-pending events, so anything that does not come back was answered
/// elsewhere and must be dropped — otherwise the modal stays on screen until
/// the app is killed.
library;

import 'package:dsh_mobile/src/frame_router.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

ServerFrame questionFrame(String eventId) => ServerFrame(
  rpcId: eventId,
  method: 'question/requested',
  payload: {
    'type': 'question/requested',
    'sessionId': 's1',
    'rpcId': eventId,
    'questions': [
      {'id': 'q1', 'header': 'Pick', 'question': 'Which one?'},
    ],
  },
);

ServerFrame approvalFrame(String eventId) => ServerFrame(
  rpcId: eventId,
  method: 'approval/requested',
  payload: {
    'type': 'approval/requested',
    'sessionId': 's1',
    'approvalId': eventId,
    'toolName': 'shell',
  },
);

void main() {
  test('host/ready routes to a stream-ready action', () {
    final action = routeHostFrame({'type': 'host/ready', 'clientId': 'c1'});
    expect(action, isA<HostStreamReady>());
    expect((action! as HostStreamReady).clientId, 'c1');
  });

  test('a question resolved while disconnected is dropped', () {
    final app = AppState();
    app.hostFrameForTest(questionFrame('evt-1'));
    expect(app.questions, hasLength(1));

    // Reconnected afterwards: the gateway re-delivers only still-pending
    // events, and this one is gone because the web GUI answered it.
    app.reconcileInteractionsAfter(DateTime.now());
    expect(app.questions, isEmpty);
  });

  test('a question re-delivered after reconnect is kept', () {
    final app = AppState();
    final readyAt = DateTime.now();
    app.hostFrameForTest(questionFrame('evt-2'));
    app.reconcileInteractionsAfter(readyAt);
    expect(app.questions, hasLength(1));
    expect(app.questions.single.rpcId, 'evt-2');
  });

  test('approvals follow the same rule', () {
    final app = AppState();
    app.hostFrameForTest(approvalFrame('appr-1'));

    final readyAt = DateTime.now();
    app.hostFrameForTest(approvalFrame('appr-2'));
    app.reconcileInteractionsAfter(readyAt);

    expect(app.approvals.map((a) => a.approvalId), ['appr-2']);
  });

  test('a cancel frame still clears the interaction immediately', () {
    final app = AppState();
    app.hostFrameForTest(questionFrame('evt-3'));
    app.hostFrameForTest(
      ServerFrame(
        rpcId: 'evt-3',
        method: 'interaction/cancelled',
        payload: {'type': 'interaction/cancelled', 'eventId': 'evt-3'},
      ),
    );
    expect(app.questions, isEmpty);
  });
}

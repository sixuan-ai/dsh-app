import 'package:dsh_mobile/src/frame_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes host session and subagent frames', () {
    final added = routeHostFrame({
      'type': 'host/session-added',
      'sessionId': 's1',
      'blank': true,
      'cwd': '/tmp',
    });
    expect(added, isA<HostSessionAdded>());
    expect((added as HostSessionAdded).isSubagent, isFalse);
    expect(added.cwd, '/tmp');

    final subagent =
        routeHostFrame({
              'type': 'host/session-added',
              'sessionId': 's2',
              'projections': {
                'values': {'subagent': true},
              },
            })
            as HostSessionAdded;
    expect(subagent.isSubagent, isTrue);
  });

  test('routes mux projection and queue snapshots', () {
    final projection =
        routeMuxFrame({
              'type': 'session/projection',
              'sessionId': 's1',
              'key': 'title',
              'seq': 9,
              'value': '新标题',
            })
            as MuxProjection;
    expect(projection.sessionId, 's1');
    expect(projection.key, 'title');
    expect(projection.seq, 9);
    expect(projection.value, '新标题');

    final queue =
        routeMuxFrame({
              'type': 'session/queue',
              'sessionId': 's1',
              'items': [
                {'id': 'q1'},
              ],
            })
            as MuxQueueSnapshot;
    expect(queue.items, hasLength(1));
  });

  test('returns null for unknown downlink frames', () {
    expect(routeHostFrame({'type': 'host/future-event'}), isNull);
    expect(routeMuxFrame({'type': 'session/future-event'}), isNull);
  });
}

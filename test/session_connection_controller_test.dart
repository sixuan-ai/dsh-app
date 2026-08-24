import 'dart:async';

import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/src/session_connection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards frames from both streams', () async {
    final mux = StreamController<ServerFrame>();
    final host = StreamController<ServerFrame>();
    final seen = <String>[];
    final controller = SessionConnectionController(
      muxStream: () => mux.stream,
      hostStream: () => host.stream,
      onMuxFrame: (frame) => seen.add('mux:${frame.rpcId}'),
      onHostFrame: (frame) => seen.add('host:${frame.rpcId}'),
      onStreamClosed: (_) {},
    );
    controller.start();
    mux.add(_frame('m1'));
    host.add(_frame('h1'));
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['mux:m1', 'host:h1']);
    controller.stop();
    await mux.close();
    await host.close();
  });

  test('replace invalidates old stream completion callbacks', () async {
    final muxStreams = <StreamController<ServerFrame>>[];
    final hostStreams = <StreamController<ServerFrame>>[];
    var closed = 0;
    final controller = SessionConnectionController(
      muxStream: () {
        final stream = StreamController<ServerFrame>();
        muxStreams.add(stream);
        return stream.stream;
      },
      hostStream: () {
        final stream = StreamController<ServerFrame>();
        hostStreams.add(stream);
        return stream.stream;
      },
      onMuxFrame: (_) {},
      onHostFrame: (_) {},
      onStreamClosed: (_) => closed++,
    );
    controller.start();
    controller.replaceStreams();
    await muxStreams.first.close();
    await hostStreams.first.close();
    await Future<void>.delayed(Duration.zero);

    expect(muxStreams, hasLength(2));
    expect(hostStreams, hasLength(2));
    expect(closed, 0);
    controller.stop();
    await muxStreams.last.close();
    await hostStreams.last.close();
  });

  test('stop prevents closed streams from requesting reconnect', () async {
    final mux = StreamController<ServerFrame>();
    final host = StreamController<ServerFrame>();
    var closed = 0;
    final controller = SessionConnectionController(
      muxStream: () => mux.stream,
      hostStream: () => host.stream,
      onMuxFrame: (_) {},
      onHostFrame: (_) {},
      onStreamClosed: (_) => closed++,
    );
    controller.start();
    controller.stop();
    await mux.close();
    await host.close();
    await Future<void>.delayed(Duration.zero);

    expect(controller.active, isFalse);
    expect(closed, 0);
  });
}

ServerFrame _frame(String rpcId) =>
    ServerFrame(rpcId: rpcId, method: 'notify', payload: const {});

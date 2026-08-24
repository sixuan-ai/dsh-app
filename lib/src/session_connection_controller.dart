/// Owns mux and host stream subscriptions and invalidates stale callbacks.
library;

import 'dart:async';

import 'protocol.dart';

typedef ServerFrameStreamFactory = Stream<ServerFrame> Function();
typedef ServerFrameHandler = void Function(ServerFrame frame);
typedef StreamClosedHandler = void Function(Object? error);

class SessionConnectionController {
  SessionConnectionController({
    required this._muxStream,
    required this._hostStream,
    required this._onMuxFrame,
    required this._onHostFrame,
    required this._onStreamClosed,
  });

  final ServerFrameStreamFactory _muxStream;
  final ServerFrameStreamFactory _hostStream;
  final ServerFrameHandler _onMuxFrame;
  final ServerFrameHandler _onHostFrame;
  final StreamClosedHandler _onStreamClosed;

  StreamSubscription<ServerFrame>? _muxSub;
  StreamSubscription<ServerFrame>? _hostSub;
  int _generation = 0;
  bool _active = false;

  bool get active => _active;

  void start() {
    _active = true;
    _openStreams();
  }

  void replaceStreams() {
    if (!_active) return;
    final mux = _muxSub;
    final host = _hostSub;
    _muxSub = null;
    _hostSub = null;
    _generation++;
    unawaited(mux?.cancel());
    unawaited(host?.cancel());
    _openStreams();
  }

  void stop() {
    if (!_active && _muxSub == null && _hostSub == null) return;
    _active = false;
    _generation++;
    final mux = _muxSub;
    final host = _hostSub;
    _muxSub = null;
    _hostSub = null;
    unawaited(mux?.cancel());
    unawaited(host?.cancel());
  }

  void _openStreams() {
    final generation = ++_generation;
    _muxSub = _muxStream().listen(
      _onMuxFrame,
      onError: (Object error) => _closed(generation, error),
      onDone: () => _closed(generation, null),
    );
    _hostSub = _hostStream().listen(
      _onHostFrame,
      onError: (Object error) => _closed(generation, error),
      onDone: () => _closed(generation, null),
    );
  }

  void _closed(int generation, Object? error) {
    if (_active && generation == _generation) _onStreamClosed(error);
  }
}

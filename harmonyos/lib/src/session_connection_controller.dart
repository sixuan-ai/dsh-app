/// Owns mux and host stream subscriptions and invalidates stale callbacks.
library;

import 'dart:async';
import 'dart:math' as math;

import 'connection_backoff.dart';
import 'protocol.dart';

typedef ServerFrameStreamFactory = Stream<ServerFrame> Function();
typedef ServerFrameHandler = void Function(ServerFrame frame);
typedef StreamClosedHandler = void Function(Object? error);
typedef TimerFactory = Timer Function(Duration delay, void Function() callback);
typedef RandomUnit = double Function();
typedef RefreshHandler = void Function();

class SessionConnectionController {
  SessionConnectionController({
    required this._muxStream,
    required this._hostStream,
    required this._onMuxFrame,
    required this._onHostFrame,
    required this._onStreamClosed,
    this._onReconnect,
    this._onStable,
    TimerFactory? timerFactory,
    RandomUnit? randomUnit,
    this._stableDuration = const Duration(minutes: 1),
  }) : _timerFactory = timerFactory ?? _defaultTimerFactory,
       _randomUnit = randomUnit ?? _defaultRandomUnit;

  final ServerFrameStreamFactory _muxStream;
  final ServerFrameStreamFactory _hostStream;
  final ServerFrameHandler _onMuxFrame;
  final ServerFrameHandler _onHostFrame;
  final StreamClosedHandler _onStreamClosed;
  final RefreshHandler? _onReconnect;
  final RefreshHandler? _onStable;
  final TimerFactory _timerFactory;
  final RandomUnit _randomUnit;
  final Duration _stableDuration;

  StreamSubscription<ServerFrame>? _muxSub;
  StreamSubscription<ServerFrame>? _hostSub;
  int _generation = 0;
  bool _active = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _stableTimer;

  bool get active => _active;
  int get reconnectAttempts => _reconnectAttempts;
  bool get reconnectScheduled => _reconnectTimer != null;

  void start() {
    _active = true;
    _openStreams();
  }

  void scheduleReconnect() {
    if (!_active || _reconnectTimer != null) return;
    final delay = reconnectDelayForAttempt(
      _reconnectAttempts,
      jitterUnit: _randomUnit() * 2 - 1,
    );
    _reconnectAttempts++;
    _reconnectTimer = _timerFactory(delay, () {
      _reconnectTimer = null;
      if (!_active) return;
      replaceStreams();
      _onReconnect?.call();
      _stableTimer?.cancel();
      _stableTimer = _timerFactory(_stableDuration, () {
        _reconnectAttempts = 0;
        _onStable?.call();
      });
    });
  }

  void resume() {
    if (!_active) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    replaceStreams();
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _reconnectAttempts = 0;
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
    if (_active && generation == _generation) {
      _onStreamClosed(error);
      scheduleReconnect();
    }
  }
}

Timer _defaultTimerFactory(Duration delay, void Function() callback) =>
    Timer(delay, callback);

double _defaultRandomUnit() => math.Random().nextDouble();

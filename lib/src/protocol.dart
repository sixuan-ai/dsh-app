/// Pure-Dart DSH web-API client for the 0.1.2 Remote protocol.
/// No Flutter imports — this file also runs from the CLI smoke tool.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

class DshError implements Exception {
  DshError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'DshError($code): $message';
}

int _rpcCounter = 0;
String mintRpcId([String prefix = 'app']) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_rpcCounter++}';

/// Compatibility frame consumed by the existing state/router layer.
class ServerFrame {
  ServerFrame({
    required this.rpcId,
    required this.method,
    required this.payload,
  });
  final String rpcId;
  final String method;
  final Map<String, dynamic> payload;
  String get type => payload['type'] as String? ?? '';
}

Future<String> directoryLogin(
  String base,
  String username,
  String password,
) async {
  final client = http.Client();
  try {
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final response = await client.post(
      Uri.parse('$root/directory/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 && body['ok'] == true) {
      final server = body['server'] as String? ?? '';
      if (server.isNotEmpty) return 'https://$server';
    }
    if (response.statusCode == 401) {
      throw DshError('directory-auth', '用户名或密码错误');
    }
    throw DshError('directory-unavailable', 'HTTP ${response.statusCode}');
  } on DshError {
    rethrow;
  } catch (error) {
    throw DshError('directory-unavailable', '$error');
  } finally {
    client.close();
  }
}

class DshApi {
  DshApi(String baseUrl, {String? username, String? password})
    : base = Uri.parse(
        baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
      ),
      _basicAuth = (username != null && username.isNotEmpty)
          ? 'Basic ${base64Encode(utf8.encode('$username:${password ?? ''}'))}'
          : null;

  final Uri base;
  final String? _basicAuth;
  final http.Client _http = http.Client();
  final Map<String, int> _followCursors = {};
  Map<String, dynamic>? _host;

  Map<String, String> get _jsonHeaders {
    final headers = <String, String>{'content-type': 'application/json'};
    final auth = _basicAuth;
    if (auth != null) headers['authorization'] = auth;
    return headers;
  }

  Map<String, String> get _wsHeaders {
    final headers = <String, String>{};
    final auth = _basicAuth;
    if (auth != null) headers['authorization'] = auth;
    return headers;
  }

  Uri get _wsBase {
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme);
  }

  void close() => _http.close();

  /// The new server exposes host facts in the first `$events` item.
  Future<Map<String, dynamic>> hostReady() async {
    final cached = _host;
    if (cached != null) return Map<String, dynamic>.from(cached);
    await for (final value in remoteStream('\$events', {'args': {}})) {
      if (value is Map && value['type'] == 'ready') {
        final host = (value['host'] as Map?)?.cast<String, dynamic>() ?? {};
        _host = {'home': host['home'], 'cwd': host['home'], 'host': host};
        return Map<String, dynamic>.from(_host!);
      }
    }
    throw DshError('transport', 'Remote \$events stream closed before ready');
  }

  /// Unary Remote call. Legacy callers continue to pass the endpoint args;
  /// the wire payload is now always wrapped as `{args: ...}`.
  Future<dynamic> call(
    String method,
    Map<String, dynamic> payload, {
    String? rpcId,
  }) async {
    final endpoint = method.contains('.')
        ? method.replaceFirst('.', '/')
        : method;
    if (endpoint == 'host/describe') return hostReady();
    if (endpoint == 'session/history') {
      return sessionHistory(
        payload['sessionId'] as String,
        beforeSeq: (payload['beforeSeq'] as num?)?.toInt(),
        maxMessages: (payload['maxMessages'] as num?)?.toInt(),
      );
    }
    if (endpoint == 'workspace/list') return workspaceList();
    if (endpoint == 'session/models') {
      final catalog =
          await call('session/modelCatalog', {}, rpcId: rpcId)
              as Map<String, dynamic>;
      return {
        'current': <String, dynamic>{},
        'routable':
            catalog['routableProviders'] is List &&
            (catalog['routableProviders'] as List).isNotEmpty,
        'groups': catalog['groups'] ?? const [],
      };
    }
    final args = Map<String, dynamic>.from(payload);
    if (endpoint == 'session/prompt' && args['requestId'] == null) {
      args['requestId'] = rpcId ?? mintRpcId('prompt');
    }
    final wireArgs = endpoint == 'session/list'
        ? <String, dynamic>{'_request': args}
        : <String, dynamic>{'request': args};
    final id = rpcId ?? mintRpcId();
    final response = await _http.post(
      base.resolve('/api/$endpoint'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'type': 'client-request',
        'rpcId': id,
        'method': endpoint,
        'payload': {
          'args': endpoint == 'session/modelCatalog' ? args : wireArgs,
        },
      }),
    );
    if (response.statusCode != 200) {
      throw DshError(
        'transport',
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = (body['result'] as Map?)?.cast<String, dynamic>();
    if (result?['ok'] == true) return result!['value'];
    final error = (result?['error'] as Map?)?.cast<String, dynamic>() ?? {};
    throw DshError(
      error['code'] as String? ?? 'remote-error',
      error['message'] as String? ?? 'Remote call failed',
    );
  }

  Future<bool> respond(String rpcId, dynamic value) async {
    final response = await _http.post(
      base.resolve('/api/respond'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'type': 'client-response',
        'rpcId': rpcId,
        'result': {'ok': true, 'value': value},
      }),
    );
    if (response.statusCode != 200) return false;
    final receipt = jsonDecode(response.body) as Map<String, dynamic>;
    return receipt['accepted'] == true;
  }

  /// Opens one logical Remote stream over the single physical mux socket.
  Stream<dynamic> remoteStream(
    String endpoint,
    Map<String, dynamic> payload,
  ) async* {
    final channel = IOWebSocketChannel.connect(
      _wsBase.resolve('/api/remote.mux'),
      pingInterval: const Duration(seconds: 20),
      headers: _wsHeaders,
    );
    final streamId = mintRpcId('stream');
    channel.sink.add(
      jsonEncode({
        'type': 'open',
        'streamId': streamId,
        'endpoint': endpoint,
        'payload': payload,
      }),
    );
    try {
      await for (final data in channel.stream) {
        final frame = jsonDecode(data as String) as Map<String, dynamic>;
        if (frame['streamId'] != streamId) continue;
        switch (frame['type']) {
          case 'item':
            yield frame['value'];
          case 'end':
            return;
          case 'error':
            final error =
                (frame['error'] as Map?)?.cast<String, dynamic>() ?? {};
            throw DshError(
              error['code'] as String? ?? 'remote-stream',
              error['message'] as String? ?? 'Remote stream failed',
            );
        }
      }
    } finally {
      await channel.sink.close();
    }
  }

  /// Compatibility stream: session/control -> the old mux frame vocabulary.
  Stream<ServerFrame> muxStream() async* {
    await for (final value in remoteStream('session/control', {'args': {}})) {
      if (value is! Map) continue;
      final type = value['type'];
      if (type == 'baseline') {
        final baseline =
            (value['value'] as Map?)?.cast<String, dynamic>() ?? {};
        final queues =
            (baseline['queues'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final entry in queues.entries) {
          yield _frame('session/queue', {
            'type': 'session/queue',
            'sessionId': entry.key,
            'items': entry.value,
          });
        }
        final projections =
            (baseline['projections'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final entry in projections.entries) {
          final p = (entry.value as Map?)?.cast<String, dynamic>() ?? {};
          final values = (p['values'] as Map?)?.cast<String, dynamic>() ?? {};
          final seq = (p['asOfSeq'] as num?)?.toInt() ?? 0;
          for (final cell in values.entries) {
            yield _frame('session/projection', {
              'type': 'session/projection',
              'sessionId': entry.key,
              'key': cell.key,
              'value': cell.value,
              'seq': seq,
            });
          }
        }
      } else if (type == 'queue' || type == 'projection') {
        final payload = Map<String, dynamic>.from(value);
        payload['type'] = type == 'queue'
            ? 'session/queue'
            : 'session/projection';
        yield _frame(payload['type'] as String, payload);
      }
    }
  }

  /// Compatibility host stream: `$events` emit frames -> old host frames.
  Stream<ServerFrame> hostStream() async* {
    await for (final value in remoteStream('\$events', {'args': {}})) {
      if (value is! Map || value['type'] != 'emit') continue;
      final event = value['event'] as String? ?? '';
      final args = (value['args'] as List?) ?? const [];
      final payload = _hostEvent(event, args);
      if (payload != null) yield _frame(event, payload);
    }
  }

  Stream<dynamic> sessionFollow(String sessionId) =>
      remoteStream('session/follow', {
        'args': {
          'request': {
            'address': {'kind': 'session', 'sessionId': sessionId},
            'maxMessages': 10,
          },
        },
      });

  Future<Map<String, dynamic>> sessionHistory(
    String sessionId, {
    int? beforeSeq,
    int? maxMessages,
  }) async {
    final limit = maxMessages ?? 10;
    if (beforeSeq == null) {
      Map<String, dynamic>? snapshot;
      await for (final value in remoteStream('session/follow', {
        'args': {
          'request': {
            'address': {'kind': 'session', 'sessionId': sessionId},
            'maxMessages': limit,
          },
        },
      })) {
        if (value is! Map) continue;
        if (value['type'] == 'snapshot') {
          snapshot = value.cast<String, dynamic>();
          break;
        }
      }
      if (snapshot == null) {
        throw DshError('remote-history', 'Session snapshot missing');
      }
      final cursor = (snapshot['cursor'] as num?)?.toInt() ?? -1;
      _followCursors[sessionId] = cursor;
      return {
        'events': _recordsToLegacy(snapshot['records']),
        'hasMore': snapshot['hasMore'] == true,
        'projections': snapshot['projections'],
      };
    }
    var through = _followCursors[sessionId];
    if (through == null) {
      final initial = await sessionHistory(sessionId, maxMessages: 1);
      through = _followCursors[sessionId] ?? -1;
      if (initial['events'] is List && (initial['events'] as List).isEmpty) {
        return {'events': const [], 'hasMore': false};
      }
    }
    // 0.1.2-alpha.4 gateway: session/page is a unary Remote method and the
    // gateway now rejects opening unary methods through the remote.mux stream
    // carrier (gateway/signature-invalid) — call it over HTTP instead.
    final page =
        await call('session/page', {
          'sessionId': sessionId,
          'throughSeq': through,
          'beforeSeq': beforeSeq,
          'maxMessages': limit,
        })
        as Map<String, dynamic>;
    return {
      'events': _recordsToLegacy(page['records']),
      'hasMore': page['hasMore'] == true,
    };
  }

  Future<Map<String, dynamic>> workspaceList() async {
    final value = await remoteStream('workspace/follow', {'args': {}}).first;
    final frame = (value as Map).cast<String, dynamic>();
    final baseline = (frame['value'] as Map?)?.cast<String, dynamic>() ?? {};
    return {
      'items': baseline['items'] ?? const [],
      'archivedSessionIds': baseline['archivedSessionIds'] ?? const [],
    };
  }

  ServerFrame _frame(String method, Map<String, dynamic> payload) =>
      ServerFrame(rpcId: mintRpcId('frame'), method: method, payload: payload);

  Map<String, dynamic>? _hostEvent(String event, List args) {
    switch (event) {
      case 'api-session/added':
        final row = (args.isNotEmpty && args.first is Map)
            ? (args.first as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        return {'type': 'host/session-added', ...row};
      case 'api-session/removed':
        return {'type': 'host/session-removed', 'sessionId': args.first};
      case 'api-session/status':
        return {
          'type': 'host/session-status',
          'sessionId': args.first,
          'running': args.length > 1 && args[1] == true,
        };
      case 'api-session/error':
        return {
          'type': 'host/agent-error',
          'sessionId': args.first,
          'message': args.length > 1 ? args[1] : '未知错误',
        };
      default:
        return null;
    }
  }

  List<Map<String, dynamic>> _recordsToLegacy(Object? raw) {
    final out = <Map<String, dynamic>>[];
    for (final record in (raw as List? ?? const [])) {
      if (record is! Map) continue;
      final type = record['type'];
      final event = (record['event'] as Map?)?.cast<String, dynamic>();
      if (event == null) continue;
      if (type == 'event') {
        out.add({'event': event});
        continue;
      }
      if (type != 'chunks') continue;
      final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final kind = event['type'] as String? ?? '';
      final count = kind == 'chunkrow/tool-call-chunks'
          ? ((data['args'] as List?)?.length ?? 0)
          : ((data['texts'] as List?)?.length ?? 0);
      var time = (event['time'] as num?)?.toInt() ?? 0;
      final seq0 = (event['seq'] as num?)?.toInt() ?? 0;
      for (var i = 0; i < count; i++) {
        if (i > 0) {
          time += ((data['dt'] as List?)?[i - 1] as num?)?.toInt() ?? 0;
        }
        Map<String, dynamic> chunk;
        if (kind == 'chunkrow/tool-call-chunks') {
          chunk = {
            'type': 'tool-call-delta',
            'index': data['index'],
            'id': data['id'],
            if (i == 0 && data['name'] != null) 'name': data['name'],
            'argumentsDelta': (data['args'] as List)[i],
          };
        } else {
          chunk = {
            'type': kind == 'chunkrow/reasoning-chunks'
                ? 'reasoning-delta'
                : 'text-delta',
            'index': data['index'],
            'text': (data['texts'] as List)[i],
          };
        }
        out.add({
          'event': {
            'type': 'assistant/chunk',
            'seq': seq0 + i,
            'time': time,
            'data': {
              'turn': data['turn'],
              'step': data['step'],
              'chunk': chunk,
            },
          },
        });
      }
    }
    return out;
  }
}

/// Pure-Dart DSH web-API client: unary HTTP RPC plus the two WebSocket
/// downlink streams (mux + host) and the /api/respond back-channel.
/// No Flutter imports — this file also runs from the CLI smoke tool.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

/// Business-level RPC failure carrying the host's error code.
class DshError implements Exception {
  DshError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'DshError($code): $message';
}

int _rpcCounter = 0;

/// Mints a wire rpcId. Uniqueness only needs to separate in-flight calls.
String mintRpcId([String prefix = 'app']) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_rpcCounter++}';

/// One server-pushed frame from a downlink stream.
class ServerFrame {
  ServerFrame({required this.rpcId, required this.method, required this.payload});

  final String rpcId;
  final String method;
  final Map<String, dynamic> payload;

  String get type => payload['type'] as String? ?? '';
}

/// Resolves a username to its dsh instance via the central directory service
/// (`POST {base}/directory/login`). Returns the instance base URL
/// (`https://<subdomain>`). Throws [DshError] with code `directory-auth` when
/// the directory rejects the credentials, and `directory-unavailable` when
/// the directory itself cannot be reached or answers unexpectedly — callers
/// typically fall back to a default server for the latter.
Future<String> directoryLogin(
    String base, String username, String password) async {
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

/// Connection to one DSH web server (the same origin the web GUI uses).
class DshApi {
  DshApi(String baseUrl, {String? username, String? password})
      : base = Uri.parse(baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl),
        _basicAuth = (username != null && username.isNotEmpty)
            ? 'Basic ${base64Encode(utf8.encode('$username:${password ?? ''}'))}'
            : null;

  /// Server origin, e.g. `http://127.0.0.1:3080` or the public frp URL.
  final Uri base;

  /// Prebuilt Authorization header for deployments that gate the API behind
  /// HTTP Basic (e.g. the dsh-auth-proxy gateway in front of dsh web).
  final String? _basicAuth;

  final http.Client _http = http.Client();

  Map<String, String> get _jsonHeaders => {
        'content-type': 'application/json',
        if (_basicAuth != null) 'authorization': _basicAuth,
      };

  Uri get _wsBase {
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme);
  }

  void close() {
    _http.close();
  }

  /// Unary client-request: POST /api/METHOD with the wire envelope.
  /// Returns the result value; throws [DshError] on a business failure.
  Future<dynamic> call(String method, Map<String, dynamic> payload,
      {String? rpcId}) async {
    final id = rpcId ?? mintRpcId();
    final response = await _http.post(
      base.resolve('/api/$method'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'type': 'client-request',
        'rpcId': id,
        'method': method,
        'payload': payload,
      }),
    );
    if (response.statusCode != 200) {
      throw DshError('transport', 'HTTP ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>;
    if (result['ok'] == true) return result['value'];
    final error = result['error'] as Map<String, dynamic>;
    throw DshError(error['code'] as String, error['message'] as String);
  }

  /// Answers one answerable server-request (approval/question) via
  /// POST /api/respond, echoing its rpcId. Returns false when the host no
  /// longer has that request pending.
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

  /// Opens the all-session mux stream (downlink-only WebSocket).
  Stream<ServerFrame> muxStream() => _downlink('/api/events.mux');

  /// Opens the host-level stream (session lifecycle, workspace changes).
  Stream<ServerFrame> hostStream() => _downlink('/api/events.host');

  Stream<ServerFrame> _downlink(String path) {
    final channel = IOWebSocketChannel.connect(
      _wsBase.resolve(path),
      pingInterval: const Duration(seconds: 20),
      headers: {if (_basicAuth != null) 'authorization': _basicAuth},
    );
    return channel.stream.map((data) {
      final full = jsonDecode(data as String) as Map<String, dynamic>;
      return ServerFrame(
        rpcId: full['rpcId'] as String,
        method: full['method'] as String? ?? '',
        payload: (full['payload'] as Map).cast<String, dynamic>(),
      );
    });
  }
}

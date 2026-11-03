/// One-use desktop pairing; the QR never carries a permanent device password.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'connector_transport.dart';

Uri _httpsOrigin(String value, {bool root = false}) {
  final u = Uri.tryParse(value);
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasQuery ||
      u.hasFragment ||
      (root && u.path.isNotEmpty && u.path != '/')) {
    throw const FormatException('连接地址必须是 HTTPS，不能包含账号、查询参数或片段');
  }
  return u;
}

class ConnectorPairing {
  ConnectorPairing._(this.payload);
  final Map<String, dynamic> payload;
  factory ConnectorPairing.parse(String input, {DateTime? now}) {
    Map<String, dynamic> m;
    try {
      final text = input.trim();
      if (text.length > 8192) throw const FormatException();
      if (text.startsWith('{')) {
        final raw = jsonDecode(text) as Map<String, dynamic>;
        m = (raw['payload'] as Map?)?.cast<String, dynamic>() ?? raw;
      } else {
        final u = Uri.parse(text);
        if (u.scheme != 'xharness' || u.host != 'pair') {
          throw const FormatException();
        }
        final bytes = base64Url.decode(
          base64Url.normalize(u.queryParameters['data'] ?? ''),
        );
        m = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      }
      final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
      if (m['version'] != 1 ||
          !RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
          ).hasMatch(m['nodeId'] as String? ?? '') ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(m['id'] as String? ?? '') ||
          !RegExp(
            r'^[A-Za-z0-9_-]{43}$',
          ).hasMatch(m['code'] as String? ?? '') ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(m['fingerprint'] as String? ?? '') ||
          m['expiresAt'] is! int ||
          m['expiresAt'] <= stamp ||
          m['expiresAt'] > stamp + 300000) {
        throw const FormatException();
      }
      _httpsOrigin(m['endpoint'] as String, root: true);
      return ConnectorPairing._(m);
    } catch (_) {
      throw const FormatException('配对信息无效或已过期，请在电脑重新生成二维码');
    }
  }
  String get name => payload['name'] as String? ?? '我的电脑';
  String get endpoint => payload['endpoint'] as String;
  String get fingerprint => payload['fingerprint'] as String;

  Future<PairedComputer> claim({String deviceName = 'xHarness 手机'}) async {
    final origin = Uri.parse(endpoint);
    final client = IOClient(connectorHttpClient(origin, fingerprint));
    try {
      final info = await client
          .get(origin.resolve('/connector/info'))
          .timeout(const Duration(seconds: 8));
      final metadata = jsonDecode(info.body) as Map;
      if (info.statusCode != 200 || metadata['nodeId'] != payload['nodeId']) {
        throw const FormatException('电脑身份不匹配');
      }
      final response = await client
          .post(
            origin.resolve('/connector/pair'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'id': payload['id'],
              'code': payload['code'],
              'name': deviceName,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw const FormatException('配对码已使用、过期或被拒绝，请重新生成');
      }
      final result = (jsonDecode(response.body) as Map).cast<String, dynamic>();
      if (result['nodeId'] != payload['nodeId'] ||
          !RegExp(
            r'^device-[a-f0-9-]{36}$',
          ).hasMatch(result['username'] as String? ?? '') ||
          !RegExp(
            r'^[A-Za-z0-9_-]{43}$',
          ).hasMatch(result['password'] as String? ?? '')) {
        throw const FormatException('电脑返回了无效的设备凭据');
      }
      final remote = result['remoteUrl'] as String?;
      if (remote != null) _httpsOrigin(remote);
      return PairedComputer(
        nodeId: result['nodeId'] as String,
        name: name,
        localUrl: endpoint,
        remoteUrl: remote,
        fingerprint: fingerprint,
        username: result['username'] as String,
        password: result['password'] as String,
      );
    } finally {
      client.close();
    }
  }
}

class PairedComputer {
  const PairedComputer({
    required this.nodeId,
    required this.name,
    required this.localUrl,
    required this.fingerprint,
    required this.username,
    required this.password,
    this.remoteUrl,
  });
  final String nodeId, name, localUrl, fingerprint, username, password;
  final String? remoteUrl;
  bool containsUrl(String url) => url == localUrl || url == remoteUrl;
  String? pinFor(String url) => url == localUrl ? fingerprint : null;
  String get cacheScope => 'https://$nodeId.paired.xharness.invalid';
  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'name': name,
    'localUrl': localUrl,
    'remoteUrl': remoteUrl,
    'fingerprint': fingerprint,
    'username': username,
    'password': password,
  };
  factory PairedComputer.fromJson(Map<String, dynamic> m) {
    if (!RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
        ).hasMatch(m['nodeId'] as String? ?? '') ||
        m['name'] is! String) {
      throw const FormatException('保存的电脑身份无效');
    }
    final local = m['localUrl'] as String;
    _httpsOrigin(local, root: true);
    final remote = m['remoteUrl'] as String?;
    if (remote != null) _httpsOrigin(remote);
    if (!RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(m['fingerprint'] as String? ?? '') ||
        !RegExp(
          r'^device-[a-f0-9-]{36}$',
        ).hasMatch(m['username'] as String? ?? '') ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(m['password'] as String? ?? '')) {
      throw const FormatException('保存的配对凭据无效');
    }
    return PairedComputer(
      nodeId: m['nodeId'] as String,
      name: m['name'] as String,
      localUrl: local,
      remoteUrl: remote,
      fingerprint: m['fingerprint'] as String,
      username: m['username'] as String,
      password: m['password'] as String,
    );
  }
}

class ConnectorRegistry {
  const ConnectorRegistry({this.computers = const [], this.activeNodeId});
  final List<PairedComputer> computers;
  final String? activeNodeId;
  PairedComputer? get active {
    for (final computer in computers) {
      if (computer.nodeId == activeNodeId) return computer;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'activeNodeId': activeNodeId,
    'computers': computers.map((p) => p.toJson()).toList(),
  };
  factory ConnectorRegistry.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 2 || value['computers'] is! List) {
      throw const FormatException('电脑列表无效');
    }
    final computers = (value['computers'] as List)
        .map((p) => PairedComputer.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
    final active = value['activeNodeId'] as String?;
    if (computers.length > 64 ||
        computers.map((p) => p.nodeId).toSet().length != computers.length ||
        (active != null && !computers.any((p) => p.nodeId == active))) {
      throw const FormatException('电脑列表身份无效');
    }
    return ConnectorRegistry(computers: computers, activeNodeId: active);
  }
}

class ConnectorStore {
  ConnectorStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage storage;
  static const _legacyKey = 'xharness.paired.active.v1';
  static const _key = 'xharness.paired.computers.v2';
  static Future<void> _pending = Future<void>.value();

  Future<ConnectorRegistry> loadRegistry() async {
    final raw = await storage.read(key: _key);
    try {
      if (raw != null) {
        return ConnectorRegistry.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      }
      final old = await storage.read(key: _legacyKey);
      if (old == null) return const ConnectorRegistry();
      final computer = PairedComputer.fromJson(
        (jsonDecode(old) as Map).cast<String, dynamic>(),
      );
      return ConnectorRegistry(
        computers: [computer],
        activeNodeId: computer.nodeId,
      );
    } catch (_) {
      throw const FormatException('保存的电脑密钥无效，请重新配对');
    }
  }

  Future<PairedComputer?> load() async => (await loadRegistry()).active;
  Future<void> _mutate(ConnectorRegistry Function(ConnectorRegistry) change) {
    final operation = _pending.then((_) async {
      final next = change(await loadRegistry());
      if (next.computers.length > 64) {
        throw const FormatException('最多保存 64 台电脑');
      }
      await storage.write(key: _key, value: jsonEncode(next.toJson()));
      await storage.delete(key: _legacyKey);
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> save(PairedComputer computer) => _mutate(
    (old) => ConnectorRegistry(
      computers: [
        ...old.computers.where((p) => p.nodeId != computer.nodeId),
        computer,
      ],
      activeNodeId: computer.nodeId,
    ),
  );
  Future<void> select(String? nodeId) => _mutate((old) {
    if (nodeId != null && !old.computers.any((p) => p.nodeId == nodeId)) {
      throw const FormatException('未保存这台电脑');
    }
    return ConnectorRegistry(computers: old.computers, activeNodeId: nodeId);
  });
  Future<void> forget({String? nodeId}) => _mutate((old) {
    final id = nodeId ?? old.activeNodeId;
    return ConnectorRegistry(
      computers: old.computers.where((p) => p.nodeId != id).toList(),
      activeNodeId: old.activeNodeId == id ? null : old.activeNodeId,
    );
  });
  Future<void> clear() => _mutate((_) => const ConnectorRegistry());
}

import 'dart:async';
import 'dart:convert';
import 'package:dsh_mobile/connector_pairing_page.dart';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing2/qrcode.dart';

const node = '12345678-1234-1234-1234-123456789abc';
Map<String, dynamic> payload() => {
  'version': 1,
  'nodeId': node,
  'name': '我的电脑',
  'endpoint': 'https://192.168.1.20:3082',
  'fingerprint': 'a' * 64,
  'id': 'b' * 32,
  'code': 'c' * 43,
  'expiresAt': DateTime.now().millisecondsSinceEpoch + 120000,
};
PairedComputer computer({String? remote}) => PairedComputer(
  nodeId: node,
  name: '我的电脑',
  localUrl: 'https://192.168.1.20:3082',
  fingerprint: 'a' * 64,
  username: 'device-$node',
  password: 'c' * 43,
  remoteUrl: remote,
);

class RouteState extends AppState {
  RouteState(this.localAvailable);
  final bool localAvailable;
  Completer<bool>? blockedProbe;
  final routes = <String>[];
  @override
  bool get connected => routes.isNotEmpty;
  @override
  Future<bool> probeServer(
    String url, {
    String? username,
    String? password,
    String? launchToken,
    String? certificateFingerprint,
    Duration timeout = const Duration(seconds: 3),
  }) async => blockedProbe?.future ?? localAvailable;
  @override
  Future<void> connect(
    String url, {
    String? username,
    String? password,
    String? launchToken,
  }) async {
    routes.add(url);
    serverUrl = url;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'accepts one-use link and exported JSON; rejects expired and unsafe URLs',
    () {
      final p = payload();
      final link =
          'xharness://pair?data=${base64UrlEncode(utf8.encode(jsonEncode(p)))}';
      expect(ConnectorPairing.parse(link).name, '我的电脑');
      expect(
        ConnectorPairing.parse(jsonEncode({'payload': p})).endpoint,
        p['endpoint'],
      );
      for (final change in [
        {'expiresAt': 0},
        {'version': 2},
        {'nodeId': '-' * 36},
        {'endpoint': 'http://192.168.1.20:3082'},
        {'endpoint': 'https://user:password@192.168.1.20:3082'},
        {'endpoint': 'https://192.168.1.20:3082/path'},
        {'fingerprint': '0' * 63},
      ]) {
        expect(
          () => ConnectorPairing.parse(jsonEncode({...p, ...change})),
          throwsFormatException,
        );
      }
    },
  );
  test('hub URL prefix survives HTTP and WebSocket endpoint creation', () {
    final api = DshApi('https://gateway.example/connector/$node/');
    expect(
      api.endpoint('/api/host.describe').toString(),
      'https://gateway.example/connector/$node/api/host.describe',
    );
    expect(
      api.endpoint('/api/remote.mux', websocket: true).toString(),
      'wss://gateway.example/connector/$node/api/remote.mux',
    );
    api.close();
  });
  test(
    'secure persistence, local-only pairing and centralized account isolation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final p = computer();
      final store = ConnectorStore();
      await store.save(p);
      expect((await store.load())!.toJson(), p.toJson());
      final state = AppState()..pairedComputer = p;
      state.authUsername = p.username;
      state.authPassword = p.password;
      expect(state.accountUsername, isNull);
      expect(state.accountPassword, isNull);
      expect(p.remoteUrl, isNull);
      expect(p.containsUrl('https://dsh.sixuanai.com'), isFalse);
      expect(
        await state.probeServer(
          'http://other-computer:3081',
          username: p.username,
          password: p.password,
        ),
        isFalse,
      );
      await store.forget();
      expect(await store.load(), isNull);
      state.dispose();
    },
  );
  test(
    'forget restores legacy route without overwriting the account password',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'authPass': 'legacy-password',
        'serverUrl': 'https://new.example',
        'pairedRoutesBackup': jsonEncode({
          'serverUrl': 'https://old.example',
          'lanServerUrl': null,
        }),
      });
      final state = AppState()..pairedComputer = computer();
      await state.forgetPairedComputer();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('serverUrl'), 'https://old.example');
      expect(prefs.getString('authPass'), 'legacy-password');
      expect(prefs.containsKey('lanServerUrl'), isFalse);
      state.dispose();
    },
  );
  test(
    'paired startup selects LAN, falls back only to its registered public route',
    () async {
      for (final available in [true, false]) {
        SharedPreferences.setMockInitialValues({});
        final p = computer(remote: 'https://gateway.example/connector/$node');
        final state = RouteState(available)..pairedComputer = p;
        await state.reconnectPairedComputer();
        expect(state.routes, [available ? p.localUrl : p.remoteUrl]);
        state.dispose();
      }
      SharedPreferences.setMockInitialValues({});
      final state = RouteState(false)..pairedComputer = computer();
      await state.reconnectPairedComputer();
      expect(state.routes, [computer().localUrl]);
      state.dispose();
    },
  );
  test('forget during a pending LAN probe cancels public fallback', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final wait = Completer<bool>();
    final state = RouteState(false)
      ..pairedComputer = computer(
        remote: 'https://gateway.example/connector/$node',
      )
      ..blockedProbe = wait;
    final reconnect = state.reconnectPairedComputer();
    await state.forgetPairedComputer();
    wait.complete(false);
    await reconnect;
    expect(state.routes, isEmpty);
    state.dispose();
  });
  test('QR import decodes a rendered pairing link', () {
    final link =
        'xharness://pair?data=${base64UrlEncode(utf8.encode(jsonEncode(payload())))}';
    final matrix = Encoder.encode(link, ErrorCorrectionLevel.l).matrix!;
    final photo = image.Image(
      width: (matrix.width + 8) * 5,
      height: (matrix.height + 8) * 5,
    );
    image.fill(photo, color: image.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) == 1) {
          image.fillRect(
            photo,
            x1: (x + 4) * 5,
            y1: (y + 4) * 5,
            x2: (x + 5) * 5 - 1,
            y2: (y + 5) * 5 - 1,
            color: image.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    expect(decodeConnectorQr(image.encodePng(photo)), link);
  });
}

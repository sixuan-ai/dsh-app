import 'dart:async';
import 'package:dsh_mobile/src/connection_access.dart';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/sixuan_account.dart';
import 'package:dsh_mobile/src/protocol.dart' show AccountComputer;
import 'package:dsh_mobile/state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sixuan_account_test.dart' show session;

class IdentityApi extends SixuanAccountApi {
  Future<void> Function()? validation;
  int logoutCalls = 0;
  @override
  Future<void> validate(SixuanSession session) async => validation?.call();
  @override
  Future<void> logout(SixuanSession session) async {
    logoutCalls++;
  }
}

class RouteState extends AppState {
  RouteState({super.identityApi});
  final routes = <String>[];
  @override
  Future<bool> probeServer(
    String url, {
    String? username,
    String? password,
    String? launchToken,
    String? certificateFingerprint,
    Duration timeout = const Duration(seconds: 3),
  }) async => false;
  @override
  Future<void> connect(
    String url, {
    String? username,
    String? password,
    String? launchToken,
  }) async {
    routes.add(url);
  }
}

class AccountRouteState extends AppState {
  AccountRouteState({super.directoryResolver});
  @override
  Future<bool> switchConnection(String url) async {
    serverUrl = url;
    return true;
  }
}

/// Exercises real switchConnection orchestration without any network I/O.
class GuestSwitchState extends RouteState {
  @override
  bool get connected => true;
  @override
  Future<bool> probeServer(
    String url, {
    String? username,
    String? password,
    String? launchToken,
    String? certificateFingerprint,
    Duration timeout = const Duration(seconds: 3),
  }) async => true;
}

final computer = PairedComputer(
  nodeId: '11111111-1111-1111-1111-111111111111',
  name: 'OMEN',
  localUrl: 'https://192.168.1.20:3082',
  remoteUrl: 'https://gateway.example/omen',
  fingerprint: 'a' * 64,
  username: 'device-11111111-1111-1111-1111-111111111111',
  password: 'b' * 43,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'local-only classification accepts private networks, rejects public endpoints',
    () {
      for (final url in [
        'http://127.0.0.1:3080',
        'https://192.168.1.2',
        'http://10.0.0.2',
        'http://172.16.0.1',
        'http://172.31.255.254',
        'https://omen.local',
        'http://[fd12::1]',
        'http://[::1]',
      ]) {
        expect(isLanConnectionUrl(url), isTrue, reason: url);
      }
      for (final url in [
        'https://dsh.sixuanai.com',
        'http://8.8.8.8',
        'http://172.32.0.1',
        'http://192.169.1.1',
        'ftp://192.168.1.2',
        'http://evil@192.168.1.2',
        'http://[2001:4860::1]',
        'garbage',
      ]) {
        expect(isLanConnectionUrl(url), isFalse, reason: url);
      }
    },
  );
  test(
    'guest entry persists and permits public routes before account validation',
    () async {
      final state = RouteState();
      addTearDown(state.dispose);
      await state.enterGuestMode();
      expect(state.hasEntryAccess, isTrue);
      expect(state.canUsePublicConnection, isTrue);
      await state.connect('https://public.example');
      expect(state.routes, ['https://public.example']);
      final restored = AppState();
      addTearDown(restored.dispose);
      await restored.restoreAppEntry();
      expect(restored.guestAccess, isTrue);
      expect(restored.canUsePublicConnection, isTrue);
    },
  );
  test(
    'guest switches a paired desktop from LAN to public with desktop identity intact',
    () async {
      final state = GuestSwitchState();
      addTearDown(state.dispose);
      await state.enterGuestMode();
      state.pairedComputer = computer;
      state.serverUrl = computer.localUrl;
      state.authUsername = computer.username;
      state.authPassword = computer.password;
      expect(await state.switchConnection(computer.remoteUrl!), isTrue);
      expect(state.routes, [computer.remoteUrl]);
      expect(state.pairedComputer, same(computer));
      expect(state.authUsername, computer.username);
      expect(state.authPassword, computer.password);
      expect(state.signedInAccount, isNull);
    },
  );
  test(
    'signed-in account permits both routes; logout preserves device pairing',
    () async {
      final api = IdentityApi();
      final state = RouteState(identityApi: api);
      addTearDown(state.dispose);
      await ConnectorStore().save(computer);
      await state.restorePairedComputers();
      await state.acceptAccountSession(session());
      expect(state.canUsePublicConnection, isTrue);
      await state.reconnectPairedComputer();
      expect(state.routes.last, computer.remoteUrl);
      state.routes.clear();
      await state.signOutAppAccount();
      await Future<void>.delayed(Duration.zero);
      expect(state.routes, [computer.remoteUrl]);
      expect(state.guestAccess, isTrue);
      expect(api.logoutCalls, 1);
      expect((await ConnectorStore().load())?.nodeId, computer.nodeId);
      expect(state.savedPairedComputers.single.nodeId, computer.nodeId);
    },
  );
  test(
    'restored and expired account sessions keep desktop public access',
    () async {
      final api = IdentityApi();
      final state = AppState(identityApi: api);
      addTearDown(state.dispose);
      await SixuanAccountStore().save(session());
      await state.restoreAppEntry();
      expect(state.hasEntryAccess, isTrue);
      expect(state.canUsePublicConnection, isTrue);
      expect(await state.verifyAppAccount(), isTrue);
      expect(state.canUsePublicConnection, isTrue);
      api.validation = () async =>
          throw const SixuanAccountError('expired', status: 401);
      expect(await state.verifyAppAccount(), isFalse);
      expect(state.signedInAccount, isNull);
      expect(state.guestAccess, isTrue);
      expect(state.verifyingAccount, isFalse);
      expect(await SixuanAccountStore().load(), isNull);
    },
  );
  test('a late failed validation cannot sign out a newer login', () async {
    final pending = Completer<void>();
    final api = IdentityApi()..validation = () => pending.future;
    final state = AppState(identityApi: api);
    addTearDown(state.dispose);
    await state.acceptAccountSession(session());
    final verifying = state.verifyAppAccount();
    await state.acceptAccountSession(session(email: 'new@example.com'));
    pending.completeError(const SixuanAccountError('expired', status: 401));
    await verifying;
    expect(state.signedInAccount?.email, 'new@example.com');
    expect(state.canUsePublicConnection, isTrue);
    expect(state.verifyingAccount, isFalse);
  });
  test(
    'existing installations and guest entry both permit public routes',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.restoreAppEntry();
      expect(state.hasEntryAccess, isFalse);
      expect(state.canUsePublicConnection, isTrue);
      await state.enterGuestMode();
      expect(state.canUsePublicConnection, isTrue);
    },
  );
  test(
    'guest public account selection uses the credential guarded directory',
    () async {
      var lookups = 0;
      final state = AppState(
        directoryResolver:
            (base, {required username, required password, computerId}) async {
              lookups++;
              throw StateError('Fixture directory unavailable');
            },
      );
      addTearDown(state.dispose);
      state.authUsername = 'fixture';
      state.authPassword = 'fixture';
      await state.enterGuestMode();
      final target = AccountComputer(
        id: 'omen',
        name: 'OMEN',
        subdomain: 'public.example',
        isDefault: true,
      );
      expect(await state.switchToComputer(target), isFalse);
      expect(lookups, 1);
    },
  );
  test(
    'guest keeps two paired computers and can fall back to public without login',
    () async {
      final state = RouteState();
      addTearDown(state.dispose);
      final second = PairedComputer(
        nodeId: '22222222-2222-2222-2222-222222222222',
        name: 'x-26',
        localUrl: 'https://172.16.3.193:3082',
        remoteUrl: 'https://gateway.example/x26',
        fingerprint: 'c' * 64,
        username: 'device-22222222-2222-2222-2222-222222222222',
        password: 'd' * 43,
      );
      await state.enterGuestMode();
      await state.activatePairedComputer(computer);
      await state.activatePairedComputer(second);
      await state.activatePairedComputer(computer);
      expect(state.routes, [
        computer.remoteUrl,
        second.remoteUrl,
        computer.remoteUrl,
      ]);
      expect((await ConnectorStore().loadRegistry()).computers, hasLength(2));
      expect(state.guestAccess, isTrue);
      expect(state.signedInAccount, isNull);
      expect(state.canUsePublicConnection, isTrue);
    },
  );
  test(
    'account login and logout leave existing desktop permissions unchanged',
    () async {
      final state = AppState(identityApi: IdentityApi());
      addTearDown(state.dispose);
      final permission = ProjectionCell({'currentValue': 'workspace-write'}, 1);
      state.projections['s1'] = {'permissions': permission};
      await state.enterGuestMode();
      await state.acceptAccountSession(session());
      expect(state.projections['s1']?['permissions'], same(permission));
      await state.signOutAppAccount();
      expect(state.projections['s1']?['permissions'], same(permission));
      expect(permission.value['currentValue'], 'workspace-write');
    },
  );
  test(
    'guest can select a saved LAN account computer without directory access',
    () async {
      var lookups = 0;
      final state = AccountRouteState(
        directoryResolver:
            (base, {required username, required password, computerId}) async {
              lookups++;
              throw StateError('LAN selection must work without directory');
            },
      );
      addTearDown(state.dispose);
      state.authUsername = 'fixture';
      state.authPassword = 'fixture';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remoteServerUrl', 'https://public.example');
      await state.enterGuestMode();
      final target = AccountComputer(
        id: 'lan-omen',
        name: 'OMEN',
        subdomain: '192.168.1.2:3082',
        isDefault: true,
      );
      expect(await state.switchToComputer(target), isTrue);
      expect(lookups, 0);
      expect(state.serverUrl, target.url);
      expect(prefs.getString('connectionMode'), 'lan');
      expect(prefs.getString('lanServerUrl'), target.url);
      expect(prefs.getString('remoteServerUrl'), 'https://public.example');
    },
  );
}

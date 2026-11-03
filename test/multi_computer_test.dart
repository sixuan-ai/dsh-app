import 'dart:convert';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/localstore.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const aId = '11111111-1111-1111-1111-111111111111';
const bId = '22222222-2222-2222-2222-222222222222';
PairedComputer pc(String id, String name, {String? password}) => PairedComputer(
  nodeId: id,
  name: name,
  localUrl: 'https://${id == aId ? '192.168.1.10' : '192.168.1.20'}:3082',
  remoteUrl: 'https://gateway.example/connector/$id',
  fingerprint: 'a' * 64,
  username: 'device-$id',
  password: password ?? (id == aId ? 'a' : 'b') * 43,
);
final omen = AccountComputer(
  id: 'omen',
  name: 'OMEN 笔记本',
  subdomain: 'dsh.sixuanai.com',
  isDefault: true,
);

class TestRouteState extends AppState {
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
    serverUrl = url;
    authUsername = username;
    authPassword = password;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'old x-26 single-computer record survives migration and adding OMEN',
    () async {
      final b = pc(bId, 'x-26'), a = pc(aId, 'OMEN');
      FlutterSecureStorage.setMockInitialValues({
        'xharness.paired.active.v1': jsonEncode(b.toJson()),
      });
      final store = ConnectorStore();
      expect((await store.loadRegistry()).active!.nodeId, bId);
      await store.save(a);
      final migrated = await store.loadRegistry();
      expect(migrated.computers.map((p) => p.nodeId).toSet(), {aId, bId});
      expect(migrated.active!.nodeId, aId);
      expect(
        migrated.computers.firstWhere((p) => p.nodeId == bId).password,
        b.password,
      );
      expect(
        await const FlutterSecureStorage().read(
          key: 'xharness.paired.active.v1',
        ),
        isNull,
      );
      await store.select(bId);
      expect((await ConnectorStore().load())!.nodeId, bId);
    },
  );
  test(
    'concurrent saves preserve both devices; re-pair replaces only matching UUID',
    () async {
      final store = ConnectorStore();
      await Future.wait([
        store.save(pc(aId, 'OMEN')),
        store.save(pc(bId, 'x-26')),
      ]);
      expect((await store.loadRegistry()).computers.length, 2);
      await store.save(pc(aId, 'OMEN updated', password: 'c' * 43));
      final registry = await store.loadRegistry();
      expect(registry.computers.length, 2);
      expect(registry.active!.password, 'c' * 43);
      expect(
        registry.computers.firstWhere((p) => p.nodeId == bId).password,
        'b' * 43,
      );
    },
  );
  test(
    'forget one device and switch to account retains other saved keys',
    () async {
      final store = ConnectorStore();
      await store.save(pc(aId, 'OMEN'));
      await store.save(pc(bId, 'x-26'));
      await store.forget(nodeId: aId);
      expect((await store.load())!.nodeId, bId);
      await store.select(null);
      expect(await store.load(), isNull);
      expect((await store.loadRegistry()).computers.single.nodeId, bId);
      await expectLater(store.select(aId), throwsFormatException);
      await store.select(bId);
      expect((await store.load())!.nodeId, bId);
    },
  );
  test(
    'upgraded paired startup also restores original OMEN account entry',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'xharness.paired.active.v1': jsonEncode(pc(bId, 'x-26').toJson()),
      });
      SharedPreferences.setMockInitialValues({
        'authUser': 'original-owner',
        'authPass': 'original-password',
        'accountComputers': jsonEncode([omen.toJson()]),
      });
      final state = AppState();
      await state.restorePairedComputers();
      expect(state.pairedComputer!.name, 'x-26');
      expect(state.savedPairedComputers.length, 1);
      expect(state.computers.single.name, 'OMEN 笔记本');
      state.dispose();
    },
  );
  test(
    'switching between saved devices and account preserves list and account password',
    () async {
      SharedPreferences.setMockInitialValues({
        'authUser': 'owner',
        'authPass': 'original-password',
        'serverUrl': 'https://dsh.sixuanai.com',
        'accountComputers': jsonEncode([omen.toJson()]),
      });
      final state = TestRouteState();
      await state.activatePairedComputer(pc(aId, 'OMEN'));
      await state.activatePairedComputer(pc(bId, 'x-26'));
      expect(state.savedPairedComputers.length, 2);
      expect(state.computers.single.id, 'omen');
      await state.useAccountConnection();
      expect(state.pairedComputer, isNull);
      expect(state.savedPairedComputers.length, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('serverUrl'), 'https://dsh.sixuanai.com');
      expect(prefs.getString('authPass'), 'original-password');
      await state.activatePairedComputer(
        state.savedPairedComputers.firstWhere((p) => p.nodeId == aId),
      );
      expect(state.authUsername, 'device-$aId');
      expect(state.pairedComputer!.nodeId, aId);
      state.dispose();
    },
  );
  test(
    'account directory resolution uses original account, never paired device credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'authUser': 'original-owner',
        'authPass': 'original-password',
      });
      final seen = <String>[];
      final state =
          AppState(
              directoryResolver:
                  (
                    base, {
                    required username,
                    required password,
                    computerId,
                  }) async {
                    seen.addAll([username, password, computerId ?? '']);
                    throw DshError('offline', 'test unavailable');
                  },
            )
            ..pairedComputer = pc(bId, 'x-26')
            ..authUsername = 'device-$bId'
            ..authPassword = 'b' * 43;
      expect(await state.switchToComputer(omen), isFalse);
      expect(seen, ['original-owner', 'original-password', 'omen']);
      expect(state.pairedComputer!.nodeId, bId);
      state.dispose();
    },
  );
  test(
    'logout cancels a computer selection that is still awaiting persistence',
    () async {
      final state = TestRouteState();
      final pending = state.activatePairedComputer(pc(bId, 'x-26'));
      await state.clearPairedComputers();
      await pending;
      expect(state.pairedComputer, isNull);
      expect(state.savedPairedComputers, isEmpty);
      expect((await ConnectorStore().loadRegistry()).computers, isEmpty);
      expect(state.authUsername, isNull);
      state.dispose();
    },
  );
  test(
    'paired caches are stable for each computer and isolated across computers',
    () {
      final a = pc(aId, 'OMEN'), b = pc(bId, 'x-26');
      final aStore = LocalStore.forServer(a.cacheScope, a.nodeId),
          bStore = LocalStore.forServer(b.cacheScope, b.nodeId);
      expect(aStore.dbFileName, isNot(bStore.dbFileName));
      expect(
        LocalStore.forServer(pc(aId, 'renamed').cacheScope, aId).dbFileName,
        aStore.dbFileName,
      );
    },
  );
}

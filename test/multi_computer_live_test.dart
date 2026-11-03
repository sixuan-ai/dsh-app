/// Opt-in read-only integration check. The orchestrator supplies short-lived
/// test device credentials and deletes the private input file after execution.
library;

import 'dart:convert';
import 'dart:io';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final input = Platform.environment['XHARNESS_LIVE_PROFILE_FILE'];
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real x-26 → original OMEN account → paired OMEN → x-26 retains both computers',
    () async {
      HttpOverrides.global = null;
      final data = jsonDecode(await File(input!).readAsString()) as Map;
      final a = PairedComputer.fromJson(
        (data['omen'] as Map).cast<String, dynamic>(),
      );
      final b = PairedComputer.fromJson(
        (data['x26'] as Map).cast<String, dynamic>(),
      );
      final legacy = (data['account'] as Map).cast<String, dynamic>();
      final accountComputer = AccountComputer.fromJson(
        (legacy['computer'] as Map).cast<String, dynamic>(),
      );
      final dbDir = await Directory.systemTemp.createTemp(
        'xharness-switch-db-',
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(dbDir.path);
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'authUser': legacy['username'],
        'authPass': legacy['password'],
        'serverUrl': 'https://dsh.sixuanai.com',
        'remoteServerUrl': 'https://dsh.sixuanai.com',
        'accountComputers': jsonEncode([accountComputer.toJson()]),
      });
      final store = ConnectorStore();
      await store.save(a);
      await store.select(null);
      final state = AppState();
      Future<Set<String>> snapshot() async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (state.sessions.isEmpty && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(state.connected, isTrue);
        expect(state.sessions.isNotEmpty, isTrue);
        return state.sessions.map((s) => s.sessionId).toSet();
      }

      try {
        await state.restorePairedComputers();
        await state.activatePairedComputer(b);
        final x26 = await snapshot();
        expect(state.computers.any((c) => c.id == accountComputer.id), isTrue);
        expect(await state.switchToComputer(accountComputer), isTrue);
        final originalOmen = await snapshot();
        expect(state.pairedComputer, isNull);
        expect(state.savedPairedComputers.length, 2);
        expect(state.authUsername == legacy['username'], isTrue);
        await state.activatePairedComputer(a);
        final pairedOmen = await snapshot();
        expect(pairedOmen, originalOmen);
        await state.activatePairedComputer(b);
        final reopened = await snapshot();
        expect(reopened, x26);
        final restored = await ConnectorStore().loadRegistry();
        expect(restored.computers.length, 2);
        expect(restored.activeNodeId, b.nodeId);
        stdout.writeln(
          'PASS actual account/paired switches: OMEN ${originalOmen.length} sessions, x-26 ${x26.length} sessions; both profiles retained',
        );
      } finally {
        state.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await dbDir.delete(recursive: true);
      }
    },
    skip: input == null
        ? 'Set XHARNESS_LIVE_PROFILE_FILE for the explicit read-only live check'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

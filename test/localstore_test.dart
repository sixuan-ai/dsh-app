/// Unit tests for the chunked SQLite conversation cache: round trips,
/// dirty-chunk-only writes, shrink handling, and the v1 → v2 migration.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dsh_mobile/src/localstore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Serializes [items] the way state.dart does: fixed chunk size, one JSON
/// array of item maps per chunk.
List<String> encodeChunks(List<Map<String, dynamic>> items) {
  final chunks = <String>[];
  for (var i = 0; i < items.length; i += kChatChunkSize) {
    final end =
        i + kChatChunkSize > items.length ? items.length : i + kChatChunkSize;
    chunks.add(jsonEncode(items.sublist(i, end)));
  }
  return chunks;
}

List<Map<String, dynamic>> items(int count, {String prefix = 'i'}) => [
      for (var i = 0; i < count; i++) {'id': '$prefix$i', 'text': 'message $i'},
    ];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var dbCounter = 0;
  late LocalStore store;

  setUp(() async {
    // The ffi factory persists database files under .dart_tool; wipe them so
    // every run starts from a fresh on-disk state (migration tests must not
    // find yesterday's already-migrated files).
    final dir = Directory(await getDatabasesPath());
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    store = LocalStore(dbFileName: 'localstore_test_${dbCounter++}.db');
  });

  tearDown(() async {
    await store.close();
  });

  group('save/load round trip', () {
    test('empty and missing sessions', () async {
      expect(await store.loadChatItems('none'), isNull);
      await store.saveChatItems('empty', []);
      final cached = await store.loadChatItems('empty');
      expect(cached, isNotNull);
      expect(cached!.itemJsons, isEmpty);
      expect(cached.oldestSeq, isNull);
      expect(cached.hasMore, isFalse);
    });

    test('multi-chunk order and cursors survive', () async {
      final all = items(120); // 3 chunks at kChatChunkSize
      await store.saveChatItems(
        's1',
        encodeChunks(all),
        oldestSeq: 7,
        latestSeq: 999,
        hasMore: true,
      );
      final cached = await store.loadChatItems('s1');
      expect(cached!.itemJsons.length, 120);
      expect(cached.itemJsons.first['id'], 'i0');
      expect(cached.itemJsons.last['id'], 'i119');
      expect(cached.oldestSeq, 7);
      expect(cached.latestSeq, 999);
      expect(cached.hasMore, isTrue);
    });

    test('sessions are independent', () async {
      await store.saveChatItems('a', encodeChunks(items(2)));
      await store.saveChatItems(
        'b',
        encodeChunks(items(3, prefix: 'b')),
        latestSeq: 42,
      );
      expect((await store.loadChatItems('a'))!.itemJsons.length, 2);
      final b = await store.loadChatItems('b');
      expect(b!.itemJsons.length, 3);
      expect(b.itemJsons.first['id'], 'b0');
      expect(b.latestSeq, 42);
    });
  });

  group('dirty-chunk writes', () {
    test('identical save writes no chunks', () async {
      final all = items(100);
      await store.saveChatItems('s', encodeChunks(all));
      expect(store.lastChunkWrites, 2); // first save writes everything
      await store.saveChatItems('s', encodeChunks(all));
      expect(store.lastChunkWrites, 0);
    });

    test('tail append rewrites only the last chunk', () async {
      var all = items(75); // chunk 0 full, chunk 1 partial
      await store.saveChatItems('s', encodeChunks(all));
      expect(store.lastChunkWrites, 2);

      all = [...all, ...items(10, prefix: 'x')];
      await store.saveChatItems('s', encodeChunks(all));
      // Chunk 0 (items 0-49) is byte-identical; only chunk 1 changed.
      expect(store.lastChunkWrites, 1);
      expect((await store.loadChatItems('s'))!.itemJsons.length, 85);
    });

    test('in-place tail edit rewrites only the last chunk', () async {
      final all = items(100); // exactly 2 full chunks
      await store.saveChatItems('s', encodeChunks(all));

      final edited = [...items(99), {...all.last, 'text': 'edited'}];
      await store.saveChatItems('s', encodeChunks(edited));
      expect(store.lastChunkWrites, 1);
      final cached = await store.loadChatItems('s');
      expect(cached!.itemJsons.last['text'], 'edited');
      expect(cached.itemJsons[49]['text'], 'message 49'); // prefix intact
    });

    test('reopen (fresh app run) then identical save writes nothing',
        () async {
      final name = 'localstore_reopen_test.db';
      final first = LocalStore(dbFileName: name);
      await first.saveChatItems(
        's',
        encodeChunks(items(60)),
        latestSeq: 10,
        hasMore: true,
      );
      await first.close();

      final second = LocalStore(dbFileName: name);
      final cached = await second.loadChatItems('s');
      expect(cached!.itemJsons.length, 60);
      expect(cached.latestSeq, 10);
      // Re-serializing loaded content yields identical chunk JSON, so the
      // load-seeded hashes short-circuit the write.
      await second.saveChatItems(
        's',
        encodeChunks(cached.itemJsons),
        latestSeq: 10,
        hasMore: true,
      );
      expect(second.lastChunkWrites, 0,
          reason: 'load-seeded hashes should match a re-encode');
      await second.close();
    });

    test('shrinking the item count deletes surplus chunks', () async {
      await store.saveChatItems('s', encodeChunks(items(120)));
      await store.saveChatItems('s', encodeChunks(items(50)));
      final cached = await store.loadChatItems('s');
      expect(cached!.itemJsons.length, 50);
      // No stale rows behind the meta cursor.
      await store.saveChatItems('s', encodeChunks(items(50)));
      expect(store.lastChunkWrites, 0);
    });
  });

  group('v1 migration', () {
    Future<void> createV1Database(
      String name,
      List<Map<String, Object>> rows,
    ) async {
      final path = p.join(await getDatabasesPath(), name);
      final db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE chat_items ('
            'session_id TEXT PRIMARY KEY, '
            'updated_at INTEGER NOT NULL, '
            'json TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('kv', {'key': 'k', 'value': 'v'});
          for (final row in rows) {
            await db.insert('chat_items', row);
          }
        },
      );
      await db.close();
    }

    test('envelope rows keep cursors; bare lists lose them', () async {
      final name = 'localstore_migrate1_test.db';
      await createV1Database(name, [
        {
          'session_id': 'envelope',
          'updated_at': 1,
          'json': jsonEncode({
            'items': items(60),
            'oldestSeq': 3,
            'latestSeq': 88,
            'hasMore': true,
          }),
        },
        {
          'session_id': 'bare',
          'updated_at': 2,
          'json': jsonEncode(items(7)),
        },
        {'session_id': 'corrupt', 'updated_at': 3, 'json': 'not json {'},
      ]);
      final store = LocalStore(dbFileName: name);
      final envelope = await store.loadChatItems('envelope');
      expect(envelope!.itemJsons.length, 60);
      expect(envelope.oldestSeq, 3);
      expect(envelope.latestSeq, 88);
      expect(envelope.hasMore, isTrue);

      final bare = await store.loadChatItems('bare');
      expect(bare!.itemJsons.length, 7);
      expect(bare.oldestSeq, isNull, reason: 'v1 bare lists have no cursor');
      expect(bare.hasMore, isFalse);

      expect(await store.loadChatItems('corrupt'), isNull);
      expect(await store.kvRead('k'), 'v', reason: 'kv table survives');
      await store.close();

      final db = await openDatabase(
        p.join(await getDatabasesPath(), name),
        version: 2,
      );
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='chat_items'",
      );
      expect(tables, isEmpty, reason: 'legacy table is dropped');
      await db.close();
    });

    test('migrated chunks save incrementally afterwards', () async {
      final name = 'localstore_migrate2_test.db';
      await createV1Database(name, [
        {
          'session_id': 's',
          'updated_at': 1,
          'json': jsonEncode({'items': items(120)}),
        },
      ]);
      final store = LocalStore(dbFileName: name);
      final cached = await store.loadChatItems('s');
      expect(cached!.itemJsons.length, 120);
      // A tail append after migration touches only the last chunk.
      final grown = [...cached.itemJsons, ...items(1, prefix: 'new')];
      await store.saveChatItems('s', encodeChunks(grown), latestSeq: 5);
      expect(store.lastChunkWrites, 1);
      expect((await store.loadChatItems('s'))!.itemJsons.length, 121);
      await store.close();
    });
  });

  group('kv store', () {
    test('read/write/overwrite', () async {
      expect(await store.kvRead('missing'), isNull);
      await store.kvWrite('a', '1');
      await store.kvWrite('b', '中文值');
      expect(await store.kvRead('a'), '1');
      expect(await store.kvRead('b'), '中文值');
      await store.kvWrite('a', '2');
      expect(await store.kvRead('a'), '2');
    });

    test('opens with WAL journal mode (Android rejects execute pragmas)',
        () async {
      // The Android bridge throws on value-returning statements passed to
      // execute(), so the pragmas must go through rawQuery; WAL must still
      // end up enabled in the database file itself.
      await store.kvWrite('probe', 'ok');
      final db = await openDatabase(
        p.join(await getDatabasesPath(), store.dbFileName),
      );
      final mode = await db.rawQuery('PRAGMA journal_mode');
      await db.close();
      expect(mode.first['journal_mode'].toString().toLowerCase(), 'wal');
    });
  });

  test('fnv1a64 is stable and discriminates content', () {
    expect(LocalStore.fnv1a64(''), 0xcbf29ce484222325);
    expect(LocalStore.fnv1a64('abc'), LocalStore.fnv1a64('abc'));
    expect(LocalStore.fnv1a64('abc'), isNot(LocalStore.fnv1a64('abd')));
    expect(LocalStore.fnv1a64('a'), isNot(LocalStore.fnv1a64('aa')));
    expect(
      LocalStore.fnv1a64('长会话缓存分块'),
      LocalStore.fnv1a64('长会话缓存分块'),
    );
  });
}

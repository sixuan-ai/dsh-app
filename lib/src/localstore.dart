/// On-device persistence: folded chat items per session, the session list,
/// and the local user-stats counter, all in one SQLite database.
///
/// Chat items are stored in bounded chunks so a debounced snapshot save
/// rewrites only the chunks whose serialized JSON actually changed (for a
/// streaming tail that is typically just the last chunk), instead of the
/// whole conversation row.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

/// Items per cached chunk. Bounds the per-save write size: only chunks whose
/// JSON changed are rewritten, so an active tail costs one chunk, not one
/// whole-session row.
const kChatChunkSize = 50;

/// A cached conversation snapshot read back from SQLite.
@immutable
class CachedChatItems {
  const CachedChatItems({
    required this.itemJsons,
    this.oldestSeq,
    this.latestSeq,
    this.hasMore = false,
  });

  /// Decoded item maps, in conversation order.
  final List<Map<String, dynamic>> itemJsons;

  /// Server pagination cursors captured at save time. Null when the cache
  /// predates cursor tracking (v1 caches) and cannot drive beforeSeq.
  final int? oldestSeq;
  final int? latestSeq;
  final bool hasMore;
}

/// Lazily-opened SQLite store for offline snapshots of server state.
class LocalStore {
  /// [dbFileName] exists so tests can isolate databases from each other.
  LocalStore({this.dbFileName = 'dsh_mobile.db'});

  final String dbFileName;

  Database? _db;

  /// FNV-1a 64 hashes of the last-saved (or last-loaded) chunk JSON per
  /// session. Saves rewrite only chunks whose hash differs.
  final Map<String, List<int>> _savedChunkHashes = {};

  /// Number of chunk rows written by the most recent [saveChatItems]; a test
  /// observable for the dirty-chunk short-circuit.
  @visibleForTesting
  int lastChunkWrites = 0;

  /// Stable 64-bit FNV-1a over UTF-16 code units. Dart VM ints wrap at 64
  /// bits, which keeps this exact on the app's native targets.
  static int fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return hash;
  }

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = join(await getDatabasesPath(), dbFileName);
    return _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createV2Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Tables(db);
          await _migrateV1Chunks(db);
        }
      },
      onConfigure: (db) async {
        // WAL keeps reads/writes concurrent; busy_timeout avoids spurious
        // SQLITE_BUSY under the debounced snapshot writer.
        await db.execute('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA busy_timeout=3000');
      },
    );
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS chat_chunks ('
      'session_id TEXT NOT NULL, '
      'idx INTEGER NOT NULL, '
      'json TEXT NOT NULL, '
      'PRIMARY KEY (session_id, idx))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS chat_meta ('
      'session_id TEXT PRIMARY KEY, '
      'oldest_seq INTEGER, '
      'latest_seq INTEGER, '
      'has_more INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  /// Splits each legacy whole-row cache into chunks. v1 payloads were either
  /// a bare item list (no usable cursors) or a {items, oldestSeq, latestSeq,
  /// hasMore} envelope; both keep their cursor semantics.
  static Future<void> _migrateV1Chunks(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='chat_items'",
    );
    if (tables.isEmpty) return;
    final rows = await db.query('chat_items');
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final row in rows) {
      final sessionId = row['session_id'] as String;
      List items = const [];
      int? oldestSeq;
      int? latestSeq;
      var hasMore = false;
      try {
        final decoded = jsonDecode(row['json'] as String);
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map) {
          items = decoded['items'] as List? ?? const [];
          oldestSeq = (decoded['oldestSeq'] as num?)?.toInt();
          latestSeq = (decoded['latestSeq'] as num?)?.toInt();
          hasMore = decoded['hasMore'] == true;
        }
      } catch (_) {
        continue; // Corrupt rows are dropped; the cache is best-effort.
      }
      for (var i = 0; i < items.length; i += kChatChunkSize) {
        final end =
            i + kChatChunkSize > items.length ? items.length : i + kChatChunkSize;
        batch.insert(
          'chat_chunks',
          {
            'session_id': sessionId,
            'idx': i ~/ kChatChunkSize,
            'json': jsonEncode(items.sublist(i, end)),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      batch.insert(
        'chat_meta',
        {
          'session_id': sessionId,
          'oldest_seq': oldestSeq,
          'latest_seq': latestSeq,
          'has_more': hasMore ? 1 : 0,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await db.execute('DROP TABLE chat_items');
  }

  /// Reads the chunked cache for a session, if any. Also seeds the diff
  /// hashes so the next save of identical content writes nothing.
  Future<CachedChatItems?> loadChatItems(String sessionId) async {
    final db = await _open();
    final meta = await db.query(
      'chat_meta',
      columns: ['oldest_seq', 'latest_seq', 'has_more'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    if (meta.isEmpty) return null;
    final rows = await db.query(
      'chat_chunks',
      columns: ['json'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'idx',
    );
    final itemJsons = <Map<String, dynamic>>[];
    final hashes = <int>[];
    for (final row in rows) {
      final raw = row['json'] as String;
      hashes.add(fnv1a64(raw));
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          itemJsons.addAll(
            [for (final entry in decoded) (entry as Map).cast<String, dynamic>()],
          );
        }
      } catch (_) {
        // Skip corrupt chunks; the following save rewrites them.
      }
    }
    _savedChunkHashes[sessionId] = hashes;
    final m = meta.first;
    return CachedChatItems(
      itemJsons: itemJsons,
      oldestSeq: (m['oldest_seq'] as num?)?.toInt(),
      latestSeq: (m['latest_seq'] as num?)?.toInt(),
      hasMore: (m['has_more'] as int? ?? 0) == 1,
    );
  }

  /// Writes the chunked snapshot for a session, rewriting only chunks whose
  /// serialized JSON changed since the previous save or load. Surplus chunk
  /// rows are deleted when the item count shrank.
  Future<void> saveChatItems(
    String sessionId,
    List<String> chunkJsons, {
    int? oldestSeq,
    int? latestSeq,
    bool hasMore = false,
  }) async {
    final db = await _open();
    final hashes = [for (final json in chunkJsons) fnv1a64(json)];
    final previous = _savedChunkHashes[sessionId];
    final now = DateTime.now().millisecondsSinceEpoch;
    var writes = 0;
    final batch = db.batch();
    for (var i = 0; i < chunkJsons.length; i++) {
      final unchanged =
          previous != null && i < previous.length && previous[i] == hashes[i];
      if (unchanged) continue;
      batch.insert(
        'chat_chunks',
        {'session_id': sessionId, 'idx': i, 'json': chunkJsons[i]},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      writes++;
    }
    final previousCount = previous?.length ?? 0;
    for (var i = chunkJsons.length; i < previousCount; i++) {
      batch.delete(
        'chat_chunks',
        where: 'session_id = ? AND idx = ?',
        whereArgs: [sessionId, i],
      );
    }
    batch.insert(
      'chat_meta',
      {
        'session_id': sessionId,
        'oldest_seq': oldestSeq,
        'latest_seq': latestSeq,
        'has_more': hasMore ? 1 : 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
    lastChunkWrites = writes;
    _savedChunkHashes[sessionId] = hashes;
  }

  /// Reads a key-value entry (session list cache, prompt counter, …).
  Future<String?> kvRead(String key) async {
    final db = await _open();
    final rows = await db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  /// Writes a key-value entry.
  Future<void> kvWrite(String key, String value) async {
    final db = await _open();
    await db.insert('kv', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _savedChunkHashes.clear();
  }
}

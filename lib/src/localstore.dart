/// On-device persistence: folded chat items per session, the session list,
/// and the local user-stats counter, all in one SQLite database.
library;

import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

/// Lazily-opened SQLite store for offline snapshots of server state.
class LocalStore {
  LocalStore();

  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = join(await getDatabasesPath(), 'dsh_mobile.db');
    return _db = await openDatabase(
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
      },
      onConfigure: (db) async {
        // WAL keeps reads/writes concurrent; busy_timeout avoids spurious
        // SQLITE_BUSY under the debounced snapshot writer.
        await db.execute('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA busy_timeout=3000');
      },
    );
  }

  /// Reads the cached folded chat items JSON for a session, if any.
  Future<String?> loadChatItems(String sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'chat_items',
      columns: ['json'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    if (rows.isEmpty) return null;
    return rows.first['json'] as String;
  }

  /// Writes the folded chat items JSON for a session.
  Future<void> saveChatItems(String sessionId, String json) async {
    final db = await _open();
    await db.insert('chat_items', {
      'session_id': sessionId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'json': json,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
  }
}

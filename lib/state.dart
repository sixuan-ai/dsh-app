/// App state: connection lifecycle, session list, and the per-session
/// conversation fold that rebuilds chat items from raw session events.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'src/localstore.dart';
import 'src/pet.dart';
import 'src/protocol.dart';

/// Device IANA zone for prompt attribution; falls back to omission (valid
/// for non-browser callers) when the platform lookup fails.
Future<String?> _ianaTimeZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return info.identifier;
  } catch (_) {
    return null;
  }
}

/// One row in the session list.
class SessionRow {
  SessionRow({
    required this.sessionId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    this.cwd,
    this.title,
  });

  final String sessionId;
  int updatedAt;
  bool running;
  bool blank;
  String? cwd;
  String? title;
}

/// Image bytes submitted as part of a prompt.
class PromptImage {
  PromptImage({
    required this.mediaType,
    required this.data,
    this.name,
    this.width,
    this.height,
  });

  final String mediaType;
  final String data;
  final String? name;
  final int? width;
  final int? height;
}

/// An image reference in a durable user or assistant message.
class ChatImage {
  ChatImage({
    required this.attachmentId,
    required this.mediaType,
    this.bytes,
    this.width,
    this.height,
    this.name,
    this.data,
  });

  final String attachmentId;
  final String mediaType;
  final int? bytes;
  final int? width;
  final int? height;
  final String? name;
  String? data;
}

/// Renderable conversation unit produced by the event fold.
class ChatItem {
  ChatItem.user({
    required this.id,
    required this.text,
    this.provisional = false,
    this.images = const [],
  }) : kind = ChatItemKind.user,
       time = null;

  ChatItem.assistant({
    required this.id,
    required this.blocks,
    this.images = const [],
    this.usage,
    this.interrupted = false,
  }) : kind = ChatItemKind.assistant,
       time = null;

  ChatItem.tool({
    required this.id,
    required this.callId,
    required this.name,
    required this.arguments,
  }) : kind = ChatItemKind.tool,
       time = null;

  ChatItem.notice({required this.id, required this.text, this.isError = false})
    : kind = ChatItemKind.notice,
      time = null;

  final ChatItemKind kind;
  final String id;
  int? time;

  // user
  String text = '';
  bool provisional = false;
  List<ChatImage> images = [];

  // assistant: ordered blocks ('text' | 'reasoning')
  List<AssistantBlock> blocks = [];
  Map<String, dynamic>? usage;
  bool interrupted = false;

  // notice
  bool isError = false;

  /// A notice still awaiting its outcome (slash-command status rows): the UI
  /// renders a spinner until the paired command/done settles it.
  bool pending = false;

  // tool
  String callId = '';
  String name = '';
  String arguments = '';
  String? resultText;
  bool resultIsError = false;
  bool completed = false;
}

enum ChatItemKind { user, assistant, tool, notice }

class AssistantBlock {
  AssistantBlock(this.type, this.text);
  final String type; // 'text' | 'reasoning'
  String text;
}

/// A pending approval the user must answer.
class PendingApproval {
  PendingApproval({
    required this.rpcId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    this.reason,
  });

  final String rpcId;
  final String sessionId;
  final String approvalId;
  final String toolName;
  final String? reason;
}

/// A pending ask-user-question batch.
class PendingQuestion {
  PendingQuestion({
    required this.rpcId,
    required this.sessionId,
    required this.questions,
  });

  final String rpcId;
  final String sessionId;
  final List<Map<String, dynamic>> questions;
}

/// One projection value with its watermark (higher seq wins).
class ProjectionCell {
  ProjectionCell(this.value, this.seq);
  dynamic value;
  int seq;
}

/// Detached model catalog of one session (session.models value).
class SessionModelsData {
  SessionModelsData({
    required this.current,
    required this.routable,
    required this.groups,
  });

  final Map<String, dynamic> current;
  final bool routable;
  final List<Map<String, dynamic>> groups;

  String get label {
    final provider = current['provider'] as String? ?? '';
    final model = current['model'] as String? ?? '';
    final effort = current['reasoningEffort'] as String? ?? '';
    final base = model.isEmpty ? provider : model;
    return effort.isEmpty ? base : '$base · $effort';
  }
}

/// Root application state.
class AppState extends ChangeNotifier {
  AppState();

  DshApi? _api;
  String serverUrl = '';
  bool connecting = false;
  String? connectionError;

  final List<SessionRow> sessions = [];
  String? selectedSessionId;

  /// Server-owned archived sessions returned by workspace.archiveSession.
  final Set<String> archivedSessionIds = {};

  /// Device-local pins; pinning is intentionally independent of server order.
  final Set<String> pinnedSessionIds = {};

  /// Conversation of the selected session.
  final List<ChatItem> items = [];

  bool loadingHistory = false;
  bool hasMoreHistory = false;
  bool get selectedRunning => _sessionRunning(selectedSessionId);
  bool get selectedStreaming => _streams.isNotEmpty;

  final List<PendingApproval> approvals = [];
  final List<PendingQuestion> questions = [];

  /// Live projection values per session (title, sessionStats, tokenUsage,
  /// contextPressure, …), kept under the higher-seq-wins rule.
  final Map<String, Map<String, ProjectionCell>> projections = {};

  /// Global cumulative cache-hit input tokens across sessions; feeds the
  /// pet's growth level (1 M tokens per level).
  int petTokensTotal = 0;
  final PetTokenStore _petTokens = PetTokenStore();

  /// Folds one tokenUsage projection into the pet-growth total (per-session
  /// max wins; the projection is cumulative).
  void _trackPetTokens(String sessionId, Object? value) {
    if (value is! Map) return;
    final hit = (value['cacheReadTokens'] as num?)?.toInt();
    if (hit == null) return;
    unawaited(
      _petTokens.record(sessionId, hit).then((total) {
        if (total != petTokensTotal) {
          petTokensTotal = total;
          notifyListeners();
        }
      }),
    );
  }

  /// Seeds [petTokensTotal] from the persisted per-session maxima; the pet
  /// page calls this on open (idempotent, and test-safe — plain unit tests
  /// without a binding never construct the read).
  void ensurePetTokensLoaded() {
    unawaited(
      _petTokens.total().then((total) {
        if (total != petTokensTotal) {
          petTokensTotal = total;
          notifyListeners();
        }
      }),
    );
  }

  /// Re-reads the pet token total after an out-of-band change (pet battle
  /// settlement) so every listener sees the new level immediately.
  Future<void> refreshPetTokens() async {
    final total = await _petTokens.total();
    if (total != petTokensTotal) {
      petTokensTotal = total;
      notifyListeners();
    }
  }

  /// Model catalog of the selected session, loaded on demand.
  SessionModelsData? models;
  bool loadingModels = false;

  /// Reads one projection value for a session.
  Map<String, dynamic>? projectionOf(String? sessionId, String key) {
    if (sessionId == null) return null;
    return (projections[sessionId]?[key]?.value as Map?)
        ?.cast<String, dynamic>();
  }

  void _seedProjections(String sessionId, Map<String, dynamic>? block) {
    if (block == null) return;
    final asOf = (block['asOfSeq'] as num?)?.toInt() ?? -1;
    final values =
        (block['values'] as Map?)?.cast<String, dynamic>() ?? const {};
    final table = projections.putIfAbsent(sessionId, () => {});
    for (final entry in values.entries) {
      final cell = table[entry.key];
      if (cell == null || entry.key == 'title' || asOf >= cell.seq) {
        table[entry.key] = ProjectionCell(entry.value, asOf);
      }
    }
    final title = values['title'] as String?;
    if (title != null) _rowOf(sessionId)?.title = title;
    _trackPetTokens(sessionId, values['tokenUsage']);
  }

  /// In-flight assistant streams keyed by 'turn:step'.
  final Map<String, ChatItem> _streams = {};
  final Map<String, ChatItem> _toolItems = {};
  StreamSubscription<ServerFrame>? _muxSub;
  StreamSubscription<ServerFrame>? _hostSub;
  bool _streamsActive = false;
  Timer? _reconnectTimer;

  /// Prompts sent from this app, persisted locally; drives the user level.
  int promptCount = 0;

  /// Set when a prompt bumps the user into a new level; the UI shows a
  /// celebration and then calls [clearLevelUp].
  UserLevel? lastLevelUp;

  /// Current level derived from [promptCount].
  UserLevel get userLevel => userLevelFor(promptCount);

  void clearLevelUp() {
    lastLevelUp = null;
  }

  /// Credentials of the active connection, reused for update downloads.
  String? authUsername;
  String? authPassword;

  LocalStore? _store;
  Timer? _saveTimer;

  bool get connected => _api != null && connectionError == null;

  /// Probes a server without changing the active connection.
  Future<bool> probeServer(
    String url, {
    String? username,
    String? password,
  }) async {
    try {
      final api = DshApi(url, username: username, password: password);
      try {
        await api.call('host.describe', {}).timeout(const Duration(seconds: 3));
        return true;
      } finally {
        api.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Switches after the target passes a real DSH health check. If activation
  /// fails, reconnects the previous route with the same credentials.
  Future<bool> switchConnection(String url) async {
    final username = authUsername;
    final password = authPassword;
    final previousUrl = serverUrl;
    if (!await probeServer(url, username: username, password: password)) {
      return false;
    }
    await connect(url, username: username, password: password);
    if (connected) return true;
    if (previousUrl.isNotEmpty && previousUrl != url) {
      await connect(previousUrl, username: username, password: password);
    }
    return false;
  }

  bool _sessionRunning(String? sessionId) {
    if (sessionId == null) return false;
    for (final row in sessions) {
      if (row.sessionId == sessionId) return row.running;
    }
    return false;
  }

  SessionRow? _rowOf(String sessionId) {
    for (final row in sessions) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  /// Connects to a server and starts the downlink loops. Optional Basic
  /// credentials are forwarded on every request and the WS handshakes.
  Future<void> connect(String url, {String? username, String? password}) async {
    disconnect();
    connecting = true;
    connectionError = null;
    serverUrl = url;
    notifyListeners();
    try {
      final api = DshApi(url, username: username, password: password);
      await api.call('host.describe', {});
      _api = api;
      authUsername = username;
      authPassword = password;
      _store = LocalStore();
      // Paint the cached session list and prompt counter before the network
      // refresh so cold starts render instantly.
      await _restoreLocalSnapshot();
      _streamsActive = true;
      _startStreams();
      await refreshSessions();
    } catch (error) {
      connectionError = error.toString();
      _api = null;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _streamsActive = false;
    _reconnectTimer?.cancel();
    _backoffResetTimer?.cancel();
    _reconnectAttempts = 0;
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_muxSub?.cancel());
    unawaited(_hostSub?.cancel());
    _muxSub = null;
    _hostSub = null;
    _api?.close();
    _api = null;
    unawaited(_store?.close());
    _store = null;
    authUsername = null;
    authPassword = null;
    sessions.clear();
    items.clear();
    _itemCache.clear();
    _streams.clear();
    _toolItems.clear();
    approvals.clear();
    questions.clear();
    selectedSessionId = null;
    _lastLiveSeq = -1;
    _oldestSeq = 0;
    _loadingTail = false;
    _liveBuffer.clear();
    notifyListeners();
  }

  void _startStreams() {
    _muxSub = _api!.muxStream().listen(
      _onMuxFrame,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
    );
    _hostSub = _api!.hostStream().listen(
      _onHostFrame,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
    );
  }

  /// Reconnect backoff: 2s doubling to a 30s cap with ±25% jitter, so a
  /// downed tunnel does not get hammered and recovering peers do not
  /// reconnect in lockstep. Reset after a stable minute on the wire.
  int _reconnectAttempts = 0;
  Timer? _backoffResetTimer;

  void _scheduleReconnect() {
    if (!_streamsActive || _reconnectTimer != null) return;
    final base = math.min(2000 * math.pow(2, _reconnectAttempts), 30000);
    _reconnectAttempts++;
    final jitter = (base * 0.25 * (math.Random().nextDouble() * 2 - 1));
    final delay = Duration(milliseconds: (base + jitter).round());
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (!_streamsActive || _api == null) return;
      _startStreams();
      try {
        await refreshSessions();
        if (selectedSessionId != null) await loadHistory(selectedSessionId!);
        // Connected and synced: arm the backoff reset.
        _backoffResetTimer?.cancel();
        _backoffResetTimer = Timer(const Duration(minutes: 1), () {
          _reconnectAttempts = 0;
        });
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  /// Refreshes the sidebar session list.
  Future<void> refreshSessions() async {
    final api = _api;
    if (api == null) return;
    final value = await api.call('session.list', {}) as Map<String, dynamic>;
    final list = (value['items'] as List).cast<Map<String, dynamic>>();
    final seen = <String>{};
    for (final raw in list) {
      final id = raw['sessionId'] as String;
      seen.add(id);
      _seedProjections(
        id,
        (raw['projections'] as Map?)?.cast<String, dynamic>(),
      );
      final titleCell = projections[id]?['title']?.value;
      final title = titleCell as String?;
      final row =
          _rowOf(id) ??
          () {
            final created = SessionRow(
              sessionId: id,
              updatedAt: (raw['updatedAt'] as num).toInt(),
              running: raw['running'] == true,
              blank: raw['blank'] == true,
            );
            sessions.add(created);
            return created;
          }();
      row
        ..updatedAt = (raw['updatedAt'] as num).toInt()
        ..running = raw['running'] == true
        ..blank = raw['blank'] == true
        ..cwd = raw['cwd'] as String?
        ..title = title ?? row.title;
    }
    sessions.removeWhere((row) => !seen.contains(row.sessionId));
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // Archive membership is owned by the workspace registry, not session.list.
    // Keep the cached set on a transient failure so archived rows do not flash.
    try {
      final workspaceValue =
          await api.call('workspace.list', {}) as Map<String, dynamic>;
      archivedSessionIds
        ..clear()
        ..addAll(
          ((workspaceValue['archivedSessionIds'] as List?) ?? const [])
              .cast<String>(),
        );
      await _saveSessionMetadata();
    } catch (_) {
      // Session refresh remains usable when the workspace registry is down.
    }
    notifyListeners();
    unawaited(_saveSessionList());
  }

  /// Restores the cached session list and prompt counter from SQLite.
  Future<void> _restoreLocalSnapshot() async {
    final store = _store;
    if (store == null) return;
    try {
      promptCount = int.tryParse(await store.kvRead('promptCount') ?? '') ?? 0;
      final pinsJson = await store.kvRead('pinnedSessionIds');
      if (pinsJson != null) {
        pinnedSessionIds
          ..clear()
          ..addAll((jsonDecode(pinsJson) as List).cast<String>());
      }
      final archivedJson = await store.kvRead('archivedSessionIds');
      if (archivedJson != null) {
        archivedSessionIds
          ..clear()
          ..addAll((jsonDecode(archivedJson) as List).cast<String>());
      }
      final listJson = await store.kvRead('sessionList');
      if (listJson != null && sessions.isEmpty) {
        for (final raw
            in (jsonDecode(listJson) as List).cast<Map<String, dynamic>>()) {
          sessions.add(
            SessionRow(
              sessionId: raw['sessionId'] as String,
              updatedAt: (raw['updatedAt'] as num).toInt(),
              running: false,
              blank: raw['blank'] == true,
              cwd: raw['cwd'] as String?,
              title: raw['title'] as String?,
            ),
          );
        }
        sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
      notifyListeners();
    } catch (_) {
      // The local snapshot is best-effort; the network refresh overwrites it.
    }
  }

  Future<void> _saveSessionList() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.kvWrite(
        'sessionList',
        jsonEncode([
          for (final row in sessions)
            {
              'sessionId': row.sessionId,
              'updatedAt': row.updatedAt,
              'blank': row.blank,
              'cwd': row.cwd,
              'title': row.title,
            },
        ]),
      );
    } catch (_) {
      // Best-effort cache.
    }
  }

  /// Folded conversation cache per session, so revisiting a session renders
  /// instantly while a fresh history tail loads in the background.
  final Map<String, List<ChatItem>> _itemCache = {};

  /// Live events that arrive while a history tail load is in flight are
  /// buffered and folded after the load commits (the load clears [items]).
  bool _loadingTail = false;
  final List<Map<String, dynamic>> _liveBuffer = [];

  /// Selects a session and loads its history tail.
  Future<void> openSession(String sessionId) async {
    if (selectedSessionId == sessionId) return;
    final previous = selectedSessionId;
    if (previous != null && items.isNotEmpty) {
      _itemCache[previous] = List.of(items);
    }
    selectedSessionId = sessionId;
    items.clear();
    final cached = _itemCache[sessionId];
    if (cached != null) items.addAll(cached);
    _streams.clear();
    _toolItems.clear();
    _lastLiveSeq = -1;
    _oldestSeq = 0;
    _loadingTail = false;
    _liveBuffer.clear();
    hasMoreHistory = false;
    notifyListeners();
    if (cached == null) {
      // Cold open: paint the SQLite snapshot before the network tail arrives.
      final local = await _loadLocalItems(sessionId);
      if (selectedSessionId != sessionId) return; // user moved on
      if (local.isNotEmpty && items.isEmpty) {
        items.addAll(local);
        _rebuildToolIndex();
        notifyListeners();
      }
    }
    // A previous session's tail load may still be in flight; wait for it
    // rather than dropping this session's load on the loadingHistory guard.
    while (loadingHistory) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (selectedSessionId != sessionId) return; // user moved on
    }
    await loadHistory(sessionId);
  }

  Future<List<ChatItem>> _loadLocalItems(String sessionId) async {
    final store = _store;
    if (store == null) return const [];
    try {
      final raw = await store.loadChatItems(sessionId);
      if (raw == null) return const [];
      return [
        for (final entry in (jsonDecode(raw) as List))
          chatItemFromJson((entry as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Debounced persist of the open conversation into SQLite.
  void _scheduleSave() {
    if (selectedSessionId == null || _store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveSnapshot);
  }

  Future<void> _saveSnapshot() async {
    final sessionId = selectedSessionId;
    final store = _store;
    if (sessionId == null || store == null) return;
    // Transient stream/provisional items never reach the disk cache.
    final persistable = items
        .where((item) => !item.id.startsWith('stream-') && !item.provisional)
        .toList();
    final tail = persistable.length > 300
        ? persistable.sublist(persistable.length - 300)
        : persistable;
    try {
      await store.saveChatItems(
        sessionId,
        jsonEncode([for (final item in tail) chatItemToJson(item)]),
      );
    } catch (_) {
      // Best-effort cache.
    }
  }

  /// Loads (or prepends older pages of) the selected session's history.
  Future<void> loadHistory(String sessionId, {bool older = false}) async {
    final api = _api;
    if (api == null || loadingHistory) return;
    loadingHistory = true;
    if (!older) _loadingTail = true;
    notifyListeners();
    try {
      // Small pages: the tunnel upstream streams at ~450KB/s, and event
      // payloads carry full tool outputs, so page size dominates load time.
      final payload = <String, dynamic>{
        'sessionId': sessionId,
        'maxMessages': older ? 15 : 10,
      };
      if (older && items.isNotEmpty) {
        // beforeSeq pages align to message boundaries; use the oldest known seq.
        payload['beforeSeq'] = _oldestSeq;
      }
      final value =
          await api.call('session.history', payload) as Map<String, dynamic>;
      final entries = (value['events'] as List).cast<Map<String, dynamic>>();
      hasMoreHistory = value['hasMore'] == true;
      final folded = <ChatItem>[];
      for (final entry in entries) {
        final event = (entry['event'] as Map).cast<String, dynamic>();
        _foldEvent(event, into: folded, trackSeq: true);
      }
      if (older) {
        items.insertAll(0, folded);
        _settleOrphanedCommands();
      } else {
        items
          ..clear()
          ..addAll(folded);
        _rebuildToolIndex();
        _seedProjections(
          sessionId,
          (value['projections'] as Map?)?.cast<String, dynamic>(),
        );
        // Live dedupe watermark: frames at or below the history tail are replays.
        if (entries.isNotEmpty) {
          var maxSeq = -1;
          for (final entry in entries) {
            final seq = ((entry['event'] as Map)['seq'] as num?)?.toInt() ?? -1;
            if (seq > maxSeq) maxSeq = seq;
          }
          _lastLiveSeq = maxSeq;
        }
      }
      if (entries.isNotEmpty) {
        _oldestSeq = (((entries.first['event'] as Map)['seq']) as num).toInt();
      }
    } finally {
      loadingHistory = false;
      if (_loadingTail) {
        // Fold live events that arrived while the tail load was in flight.
        _loadingTail = false;
        final buffered = List.of(_liveBuffer);
        _liveBuffer.clear();
        for (final event in buffered) {
          _foldEvent(event);
        }
      }
      _scheduleSave();
      notifyListeners();
    }
  }

  int _oldestSeq = 0;

  /// After older pages prepend, a paged-in command/run whose command/done
  /// already folded below would spin forever: copy the settled row into the
  /// pending status and drop the standalone duplicate.
  void _settleOrphanedCommands() {
    for (final item in items) {
      if (!item.pending || !item.id.startsWith('cmdrun-')) continue;
      final doneId = 'cmddone-${item.id.substring(7)}';
      ChatItem? done;
      for (final candidate in items) {
        if (candidate.id == doneId) {
          done = candidate;
          break;
        }
      }
      if (done != null) {
        item
          ..text = done.text
          ..isError = done.isError
          ..pending = false;
        items.remove(done);
      }
    }
  }

  void _rebuildToolIndex() {
    _toolItems.clear();
    for (final item in items) {
      if (item.kind == ChatItemKind.tool) _toolItems[item.callId] = item;
    }
  }

  /// Sends a user prompt to the selected session.
  Future<bool> sendPrompt(
    String text, {
    List<PromptImage> images = const [],
  }) async {
    final api = _api;
    final sessionId = selectedSessionId;
    if (api == null ||
        sessionId == null ||
        (text.trim().isEmpty && images.isEmpty)) {
      return false;
    }
    final rpcId = mintRpcId('prompt');
    final provisional = ChatItem.user(
      id: 'local-$rpcId',
      text: text,
      provisional: true,
      images: [
        for (var index = 0; index < images.length; index++)
          ChatImage(
            attachmentId: 'local-$rpcId-$index',
            mediaType: images[index].mediaType,
            width: images[index].width,
            height: images[index].height,
            name: images[index].name,
            data: images[index].data,
          ),
      ],
    );
    items.add(provisional);
    notifyListeners();
    final timeZone = await _ianaTimeZone();
    try {
      final value =
          await api.call('session.prompt', {
                'sessionId': sessionId,
                'mode': 'queue',
                'content': [
                  if (text.trim().isNotEmpty) {'type': 'text', 'text': text},
                  for (final image in images)
                    {
                      'type': 'image',
                      'mediaType': image.mediaType,
                      'data': image.data,
                      'name': ?image.name,
                    },
                ],
                'clientTimeZone': ?timeZone,
              }, rpcId: rpcId)
              as Map<String, dynamic>;
      if (value['command'] != null) {
        // Slash commands execute server-side and never log a user/message,
        // so the provisional bubble finalizes immediately.
        provisional.provisional = false;
      } else {
        // The durable user/message event replaces the provisional echo.
        _pendingPrompts[rpcId] = provisional;
      }
      unawaited(_bumpPromptCount());
      return true;
    } catch (error) {
      items.remove(provisional);
      items.add(
        ChatItem.notice(id: 'err-$rpcId', text: '发送失败: $error', isError: true),
      );
      notifyListeners();
      return false;
    }
  }

  final Map<String, ChatItem> _pendingPrompts = {};

  /// Counts one accepted prompt and records a level-up when it crosses a
  /// threshold.
  /// Fetches durable image bytes after the server authorizes the reference.
  Future<String?> loadAttachment(ChatImage image) async {
    if (image.data != null) return image.data;
    final api = _api;
    final sessionId = selectedSessionId;
    if (api == null || sessionId == null) return null;
    try {
      final value =
          await api.call('session.attachment', {
                'sessionId': sessionId,
                'attachmentId': image.attachmentId,
              })
              as Map<String, dynamic>;
      image.data = value['data'] as String?;
      notifyListeners();
      return image.data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _bumpPromptCount() async {
    final before = userLevel.level;
    promptCount += 1;
    notifyListeners();
    try {
      await _store?.kvWrite('promptCount', '$promptCount');
    } catch (_) {
      // Best-effort counter.
    }
    if (userLevel.level > before) {
      lastLevelUp = userLevel;
      notifyListeners();
    }
  }

  /// Live slash-command catalog of the selected session (commands/list).
  Future<List<Map<String, dynamic>>> listCommands() async {
    final api = _api;
    final sessionId = selectedSessionId;
    if (api == null || sessionId == null) return const [];
    final value =
        await api.call('commands/list', {
              'args': {'agentId': sessionId},
            })
            as List;
    return value.map((c) => (c as Map).cast<String, dynamic>()).toList();
  }

  /// Locally sent command rows awaiting their command/run event, keyed by the
  /// typed line. The event adopts them by command name (recordInput:false
  /// commands omit args from the event, so exact line matching is impossible).
  final Map<String, ({ChatItem echo, ChatItem status})> _localCommandLines = {};

  /// Adds the instant local feedback for a composer-sent command: a user-style
  /// echo bubble plus a pending status notice. The command/run fold (or the
  /// RPC settle path in [runCommand]) adopts both rows in place.
  ({ChatItem echo, ChatItem status}) beginLocalCommand(String line) {
    final rpcId = mintRpcId('cmd');
    final echo = ChatItem.user(id: 'local-cmdin-$rpcId', text: line);
    final status = ChatItem.notice(
      id: 'local-cmdrun-$rpcId',
      text: '正在执行 $line …',
    )..pending = true;
    items.add(echo);
    items.add(status);
    _localCommandLines[line] = (echo: echo, status: status);
    notifyListeners();
    return (echo: echo, status: status);
  }

  ({String line, ChatItem echo, ChatItem status})? _takeLocalCommand(
    String name,
  ) {
    final prefix = '/$name';
    for (final entry in _localCommandLines.entries) {
      if (entry.key == prefix || entry.key.startsWith('$prefix ')) {
        _localCommandLines.remove(entry.key);
        return (
          line: entry.key,
          echo: entry.value.echo,
          status: entry.value.status,
        );
      }
    }
    return null;
  }

  void _replaceItem(ChatItem old, ChatItem replacement) {
    final index = items.indexOf(old);
    if (index >= 0) {
      items[index] = replacement;
    } else {
      items.add(replacement);
    }
  }

  /// Executes a slash command through the host command registry; the line is
  /// never sent to the model. Feedback is instant (local echo + pending
  /// status) and the outcome rides the command/run / command/done event pair;
  /// when the downlink missed those events, the RPC result settles the local
  /// rows under the official ids so a late event still updates in place.
  Future<void> runCommand(String line) async {
    final api = _api;
    final sessionId = selectedSessionId;
    final trimmed = line.trim();
    if (api == null || sessionId == null || trimmed.isEmpty) return;
    final local = beginLocalCommand(trimmed);
    try {
      final value =
          await api.call('commands/execute', {
                'args': {
                  'agentId': sessionId,
                  'line': trimmed,
                  'images': <String>[],
                },
              })
              as Map<String, dynamic>?;
      if (_localCommandLines.remove(trimmed) == null) {
        return; // command/run adopted the rows; command/done settles them
      }
      if (value == null) {
        // Admission miss logs no events: convert the local rows to the error.
        items.remove(local.echo);
        _replaceItem(
          local.status,
          ChatItem.notice(
            id: local.status.id,
            text: '未知命令: $trimmed · 点输入框 + 查看可用命令',
            isError: true,
          ),
        );
      } else {
        final commandId = value['commandId'] as String? ?? '';
        final result = (value['result'] as Map?)?.cast<String, dynamic>();
        final isError = result?['kind'] == 'error';
        final text = result?['text'] as String? ?? '';
        _replaceItem(
          local.echo,
          ChatItem.user(id: 'cmdin-$commandId', text: trimmed),
        );
        _replaceItem(
          local.status,
          ChatItem.notice(
            id: 'cmdrun-$commandId',
            text: text.isNotEmpty ? text : (isError ? '命令执行失败' : '执行完成'),
            isError: isError,
          ),
        );
      }
    } catch (error) {
      if (_localCommandLines.remove(trimmed) != null) {
        items.remove(local.echo);
        _replaceItem(
          local.status,
          ChatItem.notice(
            id: local.status.id,
            text: '命令发送失败: $error',
            isError: true,
          ),
        );
      }
      // Rows already adopted: the command reached the host, so the failure is
      // the connection dropping mid-flight; the connection UI reports that.
    }
    notifyListeners();
  }

  /// Cancels the selected session's active turn.
  Future<void> cancelTurn() async {
    final api = _api;
    final sessionId = selectedSessionId;
    if (api == null || sessionId == null) return;
    try {
      await api.call('session.cancel', {'sessionId': sessionId});
    } catch (_) {
      // A cancel that arrives after the turn ended is a no-op on the host.
    }
  }

  /// Creates a fresh session and selects it. [workspaceId] / [cwd] pin the
  /// working directory; both omitted uses the host default workspace.
  Future<void> createSession({String? workspaceId, String? cwd}) async {
    final api = _api;
    if (api == null) return;
    final value =
        await api.call('session.create', {
              'workspaceId': ?workspaceId,
              'cwd': ?cwd,
            })
            as Map<String, dynamic>;
    final id = value['sessionId'] as String;
    await refreshSessions();
    await openSession(id);
  }

  /// Workspace registry rows (workspace.list), loaded on demand for the
  /// new-session directory picker.
  List<Map<String, dynamic>> workspaces = [];
  bool loadingWorkspaces = false;

  /// Loads the workspace registry for the directory picker.
  Future<void> loadWorkspaces() async {
    final api = _api;
    if (api == null || loadingWorkspaces) return;
    loadingWorkspaces = true;
    notifyListeners();
    try {
      final value =
          await api.call('workspace.list', {}) as Map<String, dynamic>;
      workspaces = ((value['items'] as List?) ?? const [])
          .map((w) => (w as Map).cast<String, dynamic>())
          .toList();
      archivedSessionIds
        ..clear()
        ..addAll(
          ((value['archivedSessionIds'] as List?) ?? const []).cast<String>(),
        );
      await _saveSessionMetadata();
    } catch (_) {
      workspaces = [];
    } finally {
      loadingWorkspaces = false;
      notifyListeners();
    }
  }

  Future<void> renameSession(String sessionId, String title) async {
    final api = _api;
    if (api == null) return;
    await api.call('session.rename', {'sessionId': sessionId, 'title': title});
    _rowOf(sessionId)?.title = title;
    notifyListeners();
  }

  /// Archives a session through the host workspace registry and keeps the
  /// returned complete archive set as the authoritative local view.
  Future<void> archiveSession(String sessionId) async {
    final api = _api;
    if (api == null) return;
    final value =
        await api.call('workspace.archiveSession', {'sessionId': sessionId})
            as Map<String, dynamic>;
    archivedSessionIds
      ..clear()
      ..addAll(
        ((value['archivedSessionIds'] as List?) ?? const []).cast<String>(),
      );
    if (selectedSessionId == sessionId) {
      selectedSessionId = null;
      items.clear();
    }
    await _saveSessionMetadata();
    notifyListeners();
  }

  /// Pins or unpins a session locally; server session order is untouched.
  Future<void> setSessionPinned(String sessionId, bool pinned) async {
    if (pinned) {
      pinnedSessionIds.add(sessionId);
    } else {
      pinnedSessionIds.remove(sessionId);
    }
    await _saveSessionMetadata();
    notifyListeners();
  }

  Future<void> _saveSessionMetadata() async {
    final store = _store;
    if (store == null) return;
    await store.kvWrite(
      'pinnedSessionIds',
      jsonEncode(pinnedSessionIds.toList()),
    );
    await store.kvWrite(
      'archivedSessionIds',
      jsonEncode(archivedSessionIds.toList()),
    );
  }

  /// Loads the model catalog of the selected session.
  Future<void> loadModels() async {
    final api = _api;
    final sessionId = selectedSessionId;
    if (api == null || sessionId == null || loadingModels) return;
    loadingModels = true;
    notifyListeners();
    try {
      final value =
          await api.call('session.models', {'sessionId': sessionId})
              as Map<String, dynamic>;
      models = SessionModelsData(
        current: Map<String, dynamic>.from(
          (value['current'] as Map?) ?? const {},
        ),
        routable: value['routable'] == true,
        groups: ((value['groups'] as List?) ?? const [])
            .map((g) => (g as Map).cast<String, dynamic>())
            .toList(),
      );
    } catch (_) {
      models = null;
    } finally {
      loadingModels = false;
      notifyListeners();
    }
  }

  /// Selects the model route for the selected session.
  Future<void> selectModel(
    String provider,
    String model, {
    String? reasoningEffort,
  }) async {
    final api = _api;
    final sessionId = selectedSessionId;
    if (api == null || sessionId == null) return;
    final value =
        await api.call('session.selectModel', {
              'sessionId': sessionId,
              'provider': provider,
              'model': model,
              'reasoningEffort': ?reasoningEffort,
            })
            as Map<String, dynamic>;
    final selected = ((value['selected'] as Map?) ?? const {})
        .cast<String, dynamic>();
    models?.current.addAll(selected);
    notifyListeners();
  }

  /// Answers a pending approval. A rejected respond (the host restarted or
  /// the turn was cancelled meanwhile) surfaces as a chat notice instead of
  /// vanishing silently.
  Future<void> answerApproval(PendingApproval approval, String outcome) async {
    approvals.remove(approval);
    notifyListeners();
    final accepted = await _api?.respond(approval.rpcId, {
      'sessionId': approval.sessionId,
      'approvalId': approval.approvalId,
      'outcome': outcome,
    });
    if (accepted == false) {
      items.add(
        ChatItem.notice(
          id: 'stale-approval-${approval.rpcId}',
          text: '这条审批已失效(服务可能已重启或该轮已取消),无需处理',
        ),
      );
      notifyListeners();
    }
  }

  /// Answers a pending question batch; a rejected respond surfaces like
  /// [answerApproval]'s stale-notice.
  Future<void> answerQuestion(
    PendingQuestion question,
    List<Map<String, dynamic>> answers,
  ) async {
    questions.remove(question);
    notifyListeners();
    final accepted = await _api?.respond(question.rpcId, {
      'sessionId': question.sessionId,
      'answer': {'answers': answers},
    });
    if (accepted == false) {
      items.add(
        ChatItem.notice(
          id: 'stale-question-${question.rpcId}',
          text: '这个提问已失效(服务可能已重启或该轮已取消),你的回答未送达',
        ),
      );
      notifyListeners();
    }
  }

  // ---- downlink frames ----

  void _onHostFrame(ServerFrame frame) {
    final p = frame.payload;
    switch (p['type']) {
      case 'host/session-added':
        final id = p['sessionId'] as String;
        if (_rowOf(id) == null) {
          sessions.insert(
            0,
            SessionRow(
              sessionId: id,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              running: false,
              blank: p['blank'] == true,
              cwd: p['cwd'] as String?,
            ),
          );
        }
      case 'host/session-removed':
        sessions.removeWhere((row) => row.sessionId == p['sessionId']);
      case 'host/session-status':
        final row = _rowOf(p['sessionId'] as String);
        if (row != null) {
          row.running = p['running'] == true;
          if (row.running) {
            row.blank = false;
            row.updatedAt = DateTime.now().millisecondsSinceEpoch;
          }
        }
      case 'host/agent-error':
        if (p['sessionId'] == selectedSessionId) {
          items.add(
            ChatItem.notice(
              id: 'agenterr-${frame.rpcId}',
              text: '代理错误: ${p['message']}',
              isError: true,
            ),
          );
        }
      default:
        return;
    }
    notifyListeners();
  }

  void _onMuxFrame(ServerFrame frame) {
    final p = frame.payload;
    final sessionId = p['sessionId'] as String?;
    switch (p['type']) {
      case 'session/event':
        final event = (p['event'] as Map).cast<String, dynamic>();
        final eventSession = sessionId;
        // Track titles and blank flips list-wide; fold chat items only for the open session.
        if (event['type'] == 'session/title' && eventSession != null) {
          final data = (event['data'] as Map).cast<String, dynamic>();
          _rowOf(eventSession)?.title = data['title'] as String?;
        }
        if (eventSession == selectedSessionId) {
          _foldEvent(event);
        }
      case 'session/projection':
        if (sessionId != null) {
          final key = p['key'] as String? ?? '';
          final seq = (p['seq'] as num?)?.toInt() ?? 0;
          final table = projections.putIfAbsent(sessionId, () => {});
          final cell = table[key];
          if (cell == null || seq >= cell.seq) {
            table[key] = ProjectionCell(p['value'], seq);
          }
          if (key == 'title') _rowOf(sessionId)?.title = p['value'] as String?;
          if (key == 'tokenUsage') _trackPetTokens(sessionId, p['value']);
        }
      case 'approval/requested':
        approvals.add(
          PendingApproval(
            rpcId: frame.rpcId,
            sessionId: sessionId!,
            approvalId: p['approvalId'] as String,
            toolName: p['toolName'] as String,
            reason: p['reason'] as String?,
          ),
        );
      case 'approval/resolved':
        approvals.removeWhere((a) => a.approvalId == p['approvalId']);
      case 'question/requested':
        questions.add(
          PendingQuestion(
            rpcId: frame.rpcId,
            sessionId: sessionId!,
            questions: (p['questions'] as List).cast<Map<String, dynamic>>(),
          ),
        );
      case 'question/resolved':
        questions.removeWhere((q) => q.rpcId == p['questionRpcId']);
      default:
        return;
    }
    notifyListeners();
  }

  /// Test-only entry into the live-event fold.
  @visibleForTesting
  void foldForTest(Map<String, dynamic> event) => _foldEvent(event);

  /// Folds one raw session event into chat items. When [into] is given the
  /// produced items collect there (history paging); otherwise they append to
  /// the live conversation.
  void _foldEvent(
    Map<String, dynamic> event, {
    List<ChatItem>? into,
    bool trackSeq = false,
  }) {
    final target = into ?? items;
    final type = event['type'] as String;
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final seq = event['seq'] as int? ?? 0;
    if (into == null && _loadingTail) {
      // A history tail load clears [items] on commit; hold live events until then.
      _liveBuffer.add(event);
      return;
    }
    if (into == null && seq <= _lastLiveSeq && _lastLiveSeq >= 0) {
      return; // duplicate after reconnect
    }
    if (into == null) _lastLiveSeq = seq;

    // Items appended by this fold inherit the event timestamp (drives the
    // QQ-style time dividers in the chat list).
    final targetBefore = target.length;
    final eventTime = (event['time'] as num?)?.toInt();

    switch (type) {
      case 'user/message':
        final source =
            (data['source'] as Map?)?.cast<String, dynamic>() ?? const {};
        final kind = source['kind'];
        final content = (data['content'] as List?) ?? const [];
        final text = content
            .whereType<Map>()
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'] as String? ?? '')
            .join('\n');
        final images = content
            .whereType<Map>()
            .where((b) => b['type'] == 'image')
            .map((b) {
              final ref = (b['attachment'] as Map?)?.cast<String, dynamic>();
              if (ref == null) return null;
              return ChatImage(
                attachmentId: ref['attachmentId'] as String,
                mediaType: ref['mediaType'] as String,
                bytes: (ref['bytes'] as num?)?.toInt(),
                width: (ref['width'] as num?)?.toInt(),
                height: (ref['height'] as num?)?.toInt(),
                name: ref['name'] as String?,
              );
            })
            .whereType<ChatImage>()
            .toList();
        if (kind == 'user') {
          final rpcId = source['rpcId'] as String?;
          final provisional = rpcId != null
              ? _pendingPrompts.remove(rpcId)
              : null;
          if (provisional != null && into == null) {
            provisional
              ..text = text
              ..images = images
              ..provisional = false
              ..time ??= eventTime;
            return;
          }
          target.add(ChatItem.user(id: 'u-$seq', text: text, images: images));
        } else if (kind == 'plugin' || kind == 'goal') {
          // Injected context stays off the chat surface, mirroring the web client.
        }
      case 'assistant/message':
        final key = '${data['turn']}:${data['step']}';
        final streaming = into == null ? _streams.remove(key) : null;
        if (streaming != null) target.remove(streaming);
        final content =
            (data['message'] as Map?)?['content'] as List? ?? const [];
        final blocks = <AssistantBlock>[];
        final images = <ChatImage>[];
        for (final block in content.whereType<Map>()) {
          if (block['type'] == 'text') {
            blocks.add(AssistantBlock('text', block['text'] as String? ?? ''));
          } else if (block['type'] == 'reasoning') {
            blocks.add(
              AssistantBlock('reasoning', block['text'] as String? ?? ''),
            );
          } else if (block['type'] == 'image') {
            final ref = (block['attachment'] as Map?)?.cast<String, dynamic>();
            if (ref != null &&
                ref['attachmentId'] is String &&
                ref['mediaType'] is String) {
              images.add(
                ChatImage(
                  attachmentId: ref['attachmentId'] as String,
                  mediaType: ref['mediaType'] as String,
                  bytes: (ref['bytes'] as num?)?.toInt(),
                  width: (ref['width'] as num?)?.toInt(),
                  height: (ref['height'] as num?)?.toInt(),
                  name: ref['name'] as String?,
                ),
              );
            }
          }
        }
        if (blocks.isNotEmpty ||
            images.isNotEmpty ||
            data['interrupted'] == true) {
          target.add(
            ChatItem.assistant(
              id: 'a-$seq',
              blocks: blocks,
              images: images,
              usage: (data['usage'] as Map?)?.cast<String, dynamic>(),
              interrupted: data['interrupted'] == true,
            ),
          );
        }
      case 'assistant/chunk':
        if (into != null) {
          return; // history tail replays chunks; the final message covers them
        }
        final turn = data['turn'];
        final step = data['step'];
        final chunk = (data['chunk'] as Map).cast<String, dynamic>();
        final key = '$turn:$step';
        final item = _streams.putIfAbsent(key, () {
          final created = ChatItem.assistant(id: 'stream-$key', blocks: []);
          target.add(created);
          return created;
        });
        switch (chunk['type']) {
          case 'text-delta':
            _appendDelta(
              item,
              'text',
              chunk['index'] as int? ?? 0,
              chunk['text'] as String? ?? '',
            );
          case 'reasoning-delta':
            _appendDelta(
              item,
              'reasoning',
              chunk['index'] as int? ?? 0,
              chunk['text'] as String? ?? '',
            );
          default:
            break; // block boundaries and tool-call deltas arrive complete via other events
        }
      case 'tool/call':
        final item = ChatItem.tool(
          id: 't-$seq',
          callId: data['callId'] as String? ?? '',
          name: data['name'] as String? ?? '',
          arguments: data['arguments'] as String? ?? '',
        );
        target.add(item);
        _toolItems[item.callId] = item;
      case 'tool/result':
        final message = (data['message'] as Map?)?.cast<String, dynamic>();
        final content = (message?['content'] as List?) ?? const [];
        if (content.isNotEmpty) {
          final block = (content.first as Map).cast<String, dynamic>();
          final callId = block['toolCallId'] as String? ?? '';
          final item = _toolItems[callId];
          final text = _toolResultText(block);
          if (item != null) {
            item
              ..resultText = text
              ..resultIsError =
                  block['isError'] == true || data['error'] != null
              ..completed = true;
          } else if (into == null) {
            // Result without a seen call (page boundary): render standalone.
            final standalone =
                ChatItem.tool(
                    id: 'tr-$seq',
                    callId: callId,
                    name: 'tool',
                    arguments: '',
                  )
                  ..resultText = text
                  ..resultIsError = block['isError'] == true
                  ..completed = true;
            target.add(standalone);
          }
        }
      case 'turn/end':
        final reason = (data['reason'] as Map?)?.cast<String, dynamic>();
        if (reason?['kind'] == 'error' && into == null) {
          final failure = (reason?['error'] as Map?)?.cast<String, dynamic>();
          items.add(
            ChatItem.notice(
              id: 'turnerr-$seq',
              text: '本轮失败: ${failure?['message'] ?? '未知错误'}',
              isError: true,
            ),
          );
        }
      case 'command/run':
        // A resolved slash command entered its handler: echo the line as a
        // user-style bubble plus a pending status notice, paired with the
        // command/done row by commandId.
        final commandId = data['commandId'] as String? ?? '';
        final name = data['name'] as String? ?? '';
        if (commandId.isEmpty || name.isEmpty) break;
        var represented = false;
        for (final candidate in target) {
          if (candidate.id == 'cmdrun-$commandId') {
            represented = true;
            break;
          }
        }
        if (represented) break; // late duplicate after the RPC settled locally
        final args = data['args'] as String?;
        final line = '/$name${args ?? ''}'.trimRight();
        final local = into == null ? _takeLocalCommand(name) : null;
        final shown = local?.line ?? line;
        final echo = ChatItem.user(id: 'cmdin-$commandId', text: shown);
        final status = ChatItem.notice(
          id: 'cmdrun-$commandId',
          text: '正在执行 $shown …',
        )..pending = true;
        if (local != null) {
          _replaceItem(local.echo, echo);
          _replaceItem(local.status, status);
        } else {
          target.add(echo);
          target.add(status);
        }
      case 'command/done':
        // Slash command outcome: settle the paired pending status in place,
        // or render a standalone result row when the run predates the window.
        final commandId = data['commandId'] as String? ?? '';
        final text = data['text'] as String? ?? '';
        final isError = data['kind'] == 'error';
        ChatItem? status;
        for (final candidate in target) {
          if (candidate.id == 'cmdrun-$commandId') {
            status = candidate;
            break;
          }
        }
        if (status != null) {
          status
            ..text = text.isNotEmpty ? text : (isError ? '命令执行失败' : '执行完成')
            ..isError = isError
            ..pending = false;
        } else if (text.isNotEmpty) {
          target.add(
            ChatItem.notice(
              id: 'cmddone-$commandId',
              text: text,
              isError: isError,
            ),
          );
        }
      case 'todo/write':
        if (into == null) {
          final todos = (data['todos'] as List?) ?? const [];
          if (todos.isNotEmpty) {
            final lines = todos
                .whereType<Map>()
                .map((t) {
                  final mark = switch (t['status']) {
                    'completed' => '☑',
                    'in_progress' => '◐',
                    _ => '☐',
                  };
                  return '$mark ${t['content']}';
                })
                .join('\n');
            items.add(ChatItem.notice(id: 'todo-$seq', text: lines));
          }
        }
      default:
        break;
    }
    if (eventTime != null) {
      for (var i = targetBefore; i < target.length; i++) {
        target[i].time ??= eventTime;
      }
    }
    if (into == null) _scheduleSave();
  }

  int _lastLiveSeq = -1;

  void _appendDelta(ChatItem item, String type, int index, String delta) {
    while (item.blocks.length <= index) {
      item.blocks.add(AssistantBlock(type, ''));
    }
    final block = item.blocks[index];
    if (block.type != type) {
      // A block index reused with a new type: start a fresh visual block.
      item.blocks.insert(index, AssistantBlock(type, delta));
      return;
    }
    block.text += delta;
  }

  String _toolResultText(Map<String, dynamic> block) {
    final content = (block['content'] as List?) ?? const [];
    final parts = <String>[];
    for (final part in content.whereType<Map>()) {
      if (part['type'] == 'text') parts.add(part['text'] as String? ?? '');
      if (part['type'] == 'image') parts.add('[图片]');
    }
    return parts.join('\n');
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// Pretty-prints tool arguments JSON for the call card header.
String summarizeArguments(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return raw;
  }
}

/// Serializes a chat item for the on-device cache. Large text fields are
/// capped: the cache exists for instant rendering, not archival completeness.
Map<String, dynamic> chatItemToJson(ChatItem item) {
  String? cap(String? value) =>
      value == null || value.length <= 8000 ? value : value.substring(0, 8000);
  return {
    'kind': item.kind.name,
    'id': item.id,
    'time': item.time,
    'text': cap(item.text),
    'images': [
      for (final image in item.images)
        {
          'attachmentId': image.attachmentId,
          'mediaType': image.mediaType,
          'bytes': image.bytes,
          'width': image.width,
          'height': image.height,
          'name': image.name,
          // Keep cache metadata small; durable bytes are fetched from host.
        },
    ],
    'blocks': [
      for (final block in item.blocks)
        {'type': block.type, 'text': cap(block.text)},
    ],
    if (item.usage != null) 'usage': item.usage,
    'interrupted': item.interrupted,
    'isError': item.isError,
    'callId': item.callId,
    'name': item.name,
    'arguments': cap(item.arguments),
    'resultText': cap(item.resultText),
    'resultIsError': item.resultIsError,
    'completed': item.completed,
  };
}

/// Restores a chat item from the on-device cache.
ChatItem chatItemFromJson(Map<String, dynamic> json) {
  final kind =
      ChatItemKind.values.asNameMap()[json['kind']] ?? ChatItemKind.notice;
  final ChatItem item;
  switch (kind) {
    case ChatItemKind.user:
      item = ChatItem.user(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        images: [
          for (final raw in (json['images'] as List? ?? const []))
            ChatImage(
              attachmentId: (raw as Map)['attachmentId'] as String,
              mediaType: raw['mediaType'] as String,
              bytes: (raw['bytes'] as num?)?.toInt(),
              width: (raw['width'] as num?)?.toInt(),
              height: (raw['height'] as num?)?.toInt(),
              name: raw['name'] as String?,
            ),
        ],
      );
    case ChatItemKind.assistant:
      item = ChatItem.assistant(
        id: json['id'] as String,
        blocks: [
          for (final block in (json['blocks'] as List? ?? const []))
            AssistantBlock(
              (block as Map)['type'] as String? ?? 'text',
              block['text'] as String? ?? '',
            ),
        ],
        images: [
          for (final raw in (json['images'] as List? ?? const []))
            ChatImage(
              attachmentId: (raw as Map)['attachmentId'] as String,
              mediaType: raw['mediaType'] as String,
              bytes: (raw['bytes'] as num?)?.toInt(),
              width: (raw['width'] as num?)?.toInt(),
              height: (raw['height'] as num?)?.toInt(),
              name: raw['name'] as String?,
            ),
        ],
        usage: (json['usage'] as Map?)?.cast<String, dynamic>(),
        interrupted: json['interrupted'] == true,
      );
    case ChatItemKind.tool:
      item =
          ChatItem.tool(
              id: json['id'] as String,
              callId: json['callId'] as String? ?? '',
              name: json['name'] as String? ?? '',
              arguments: json['arguments'] as String? ?? '',
            )
            ..resultText = json['resultText'] as String?
            ..resultIsError = json['resultIsError'] == true
            ..completed = json['completed'] == true;
    case ChatItemKind.notice:
      item = ChatItem.notice(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        isError: json['isError'] == true,
      );
  }
  item.time = json['time'] as int?;
  return item;
}

/// Cumulative prompt thresholds; index i is the entry count of level i+1.
const levelThresholds = [0, 5, 15, 30, 60, 100, 160, 250, 400, 600];

/// Display title of each level, aligned with [levelThresholds].
const levelTitles = [
  '新手',
  '学徒',
  '熟手',
  '老手',
  '行家',
  '专家',
  '大师',
  '宗师',
  '传奇',
  '永恒',
];

/// User level derived from the local prompt counter.
class UserLevel {
  UserLevel({
    required this.level,
    required this.title,
    required this.count,
    required this.floor,
    this.next,
  });

  /// 1-based level number.
  final int level;
  final String title;

  /// Total prompts counted.
  final int count;

  /// Prompt count where the current level started.
  final int floor;

  /// Prompt count of the next level; null at the maximum level.
  final int? next;

  /// Progress toward the next level in [0, 1]; 1 at the maximum level.
  double get progress {
    final target = next;
    if (target == null || target == floor) return 1;
    return ((count - floor) / (target - floor)).clamp(0.0, 1.0);
  }

  /// Prompts still needed for the next level; 0 at the maximum level.
  int get remaining {
    final target = next;
    return target == null ? 0 : target - count;
  }
}

/// Computes the level for a prompt count.
UserLevel userLevelFor(int count) {
  var index = 0;
  for (var i = 0; i < levelThresholds.length; i++) {
    if (count >= levelThresholds[i]) index = i;
  }
  return UserLevel(
    level: index + 1,
    title: levelTitles[index],
    count: count,
    floor: levelThresholds[index],
    next: index + 1 < levelThresholds.length
        ? levelThresholds[index + 1]
        : null,
  );
}

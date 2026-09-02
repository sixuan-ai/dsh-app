/// App state: connection lifecycle, session list, and the per-session
/// conversation fold that rebuilds chat items from raw session events.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'src/conversation.dart';
import 'src/conversation_fold.dart';
import 'src/directory_listing.dart';
import 'src/frame_router.dart';
import 'src/localstore.dart';
import 'src/pet.dart';
import 'src/protocol.dart';
import 'src/queue.dart';
import 'src/session_connection_controller.dart';
import 'src/session_event_parser.dart';

export 'src/conversation.dart'
    show AssistantBlock, ChatImage, ChatItem, ChatItemKind;
export 'src/queue.dart' show QueuedTask;

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

/// Whether durable session metadata identifies an internal subagent session.
bool isSubagentSessionPayload(Map<String, dynamic> raw) {
  final projectionBlock = (raw['projections'] as Map?)?.cast<String, dynamic>();
  final projectionValues = (projectionBlock?['values'] as Map?)
      ?.cast<String, dynamic>();
  return raw['origin'] == 'subagent' || projectionValues?['subagent'] != null;
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
    this.isSubagent = false,
  });

  final String sessionId;
  int updatedAt;
  bool running;
  bool blank;
  String? cwd;
  String? title;
  bool isSubagent;
}

/// The collaboration mode a session currently runs in, derived from its
/// live projections (host-authoritative, kept fresh by projection frames):
/// - [goal]: a `/goal` exists and has not completed;
/// - [plan]: plan mode is active (`plan` projection `active: true`);
/// - [auto]: neither — the default free loop.
enum SessionMode { goal, plan, auto }

/// Image bytes submitted as part of a prompt.
class SubagentRow {
  const SubagentRow({
    required this.id,
    required this.mode,
    required this.activity,
    required this.hasChildren,
    this.label,
  });

  final String id;
  final String mode;
  final String activity;
  final bool hasChildren;
  final String? label;

  bool get running => activity == 'running';
}

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

class _CachedHistory {
  const _CachedHistory({
    required this.items,
    required this.oldestSeq,
    required this.latestSeq,
    required this.hasMore,
  });

  final List<ChatItem> items;
  final int? oldestSeq;
  final int? latestSeq;
  final bool hasMore;
}

class _TailItem {
  const _TailItem(this.item, this.seq);

  final ChatItem item;
  final int seq;
}

/// Root application state.
typedef QueueMutationCall =
    Future<dynamic> Function(String method, Map<String, dynamic> payload);

class AppState extends ChangeNotifier {
  AppState({@visibleForTesting this._queueMutationCall});

  DshApi? _api;
  final QueueMutationCall? _queueMutationCall;
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

  /// Server-authoritative pending inbox items for the selected session.
  final List<QueuedTask> queuedTasks = [];

  bool get hasQueuedTasks => queuedTasks.isNotEmpty;

  int get queuedTaskCount =>
      queuedTasks.where((task) => task.placement == 'queued').length;

  int get pendingTaskCount => queuedTasks.length;

  /// Replaces the text of one still-pending, text-only queued task. The queue
  /// snapshot remains authoritative and updates through `session/queue`.
  Future<bool> updateQueuedTask(String itemId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return _mutateQueuedTask(itemId, queueEditAction(trimmed));
  }

  /// Removes one still-pending queued task.
  Future<bool> removeQueuedTask(String itemId) =>
      _mutateQueuedTask(itemId, queueRemoveAction());

  Future<bool> _mutateQueuedTask(
    String itemId,
    Map<String, dynamic> action,
  ) async {
    final api = _api;
    final sessionId = selectedSessionId;
    if ((api == null && _queueMutationCall == null) ||
        sessionId == null ||
        itemId.isEmpty) {
      return false;
    }
    try {
      final call = _queueMutationCall;
      if (call != null) {
        await call('session.updateQueue', {
          'sessionId': sessionId,
          'itemId': itemId,
          'action': action,
        });
      } else {
        await api!.call('session.updateQueue', {
          'sessionId': sessionId,
          'itemId': itemId,
          'action': action,
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool loadingHistory = false;
  bool hasMoreHistory = false;

  /// A reconnect tail merge is fetching only the newest message group.
  bool syncingTail = false;

  /// A missed middle range is being filled after the newest tail became visible.
  bool fillingHistoryGap = false;

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

  /// Subagent children published for the selected parent session.
  List<SubagentRow> subagents = const [];
  bool loadingSubagents = false;

  /// Model catalog of the selected session, loaded on demand.
  SessionModelsData? models;
  bool loadingModels = false;

  /// Reads one projection value for a session.
  Map<String, dynamic>? projectionOf(String? sessionId, String key) {
    if (sessionId == null) return null;
    return (projections[sessionId]?[key]?.value as Map?)
        ?.cast<String, dynamic>();
  }

  /// The collaboration mode of a session, derived from its projections.
  SessionMode sessionModeOf(String? sessionId) {
    final goal = projectionOf(sessionId, 'goal');
    if (goal != null) {
      final phase = (goal['goal'] as Map?)?['phase'] as String?;
      // A completed goal no longer drives the loop; fall through to plan/auto.
      if (phase != 'complete') return SessionMode.goal;
    }
    final plan = projectionOf(sessionId, 'plan');
    if (plan != null && plan['active'] == true) return SessionMode.plan;
    return SessionMode.auto;
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
  final Map<String, int> _sessionTailSeqs = {};
  final Map<String, int> _subscribedLastSeqs = {};
  SessionConnectionController? _connectionController;
  StreamSubscription<dynamic>? _sessionFollowSub;
  bool _streamsActive = false;
  bool _tailSyncInFlight = false;
  bool _gapFillInFlight = false;
  int? _historyGapBeforeSeq;
  int? _historyGapAfterSeq;

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

  /// DSH's default working directory from host.describe. It lets a default
  /// session resolve to a registered workspace instead of becoming an
  /// ungrouped cwd-only session.
  String? _hostCwd;

  LocalStore? _store;
  Timer? _saveTimer;

  bool get connected => _api != null && connectionError == null;

  /// Failure detail of the most recent [probeServer] call (null on success),
  /// surfaced by the connection-switch UI when a switch is rejected.
  String? lastProbeError;

  /// Probes a server without changing the active connection. The default
  /// timeout suits LAN checks; remote routes over cellular need a longer one
  /// because a dropped first TLS handshake otherwise reads as "server down".
  Future<bool> probeServer(
    String url, {
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final api = DshApi(url, username: username, password: password);
      try {
        await api.hostReady().timeout(timeout);
        lastProbeError = null;
        return true;
      } finally {
        api.close();
      }
    } on TimeoutException {
      lastProbeError = '连接超时（${timeout.inSeconds} 秒内无响应）';
      return false;
    } catch (error) {
      lastProbeError = error.toString();
      return false;
    }
  }

  /// Lists one directory level on the connected host (read-only browse).
  /// Without [path] the backend lists the host home directory.
  Future<DirectoryListingView> listDirectory([String? path]) async {
    final client = _api;
    if (client == null) throw StateError('未连接服务器');
    final value =
        await client.call('host.listDirectory', {'path': ?path})
            as Map<String, dynamic>;
    return DirectoryListingView.fromJson(value);
  }

  /// Measures one round trip to the connected host; throws on failure.
  Future<int> pingHost() async {
    final client = _api;
    if (client == null) throw StateError('未连接服务器');
    final stopwatch = Stopwatch()..start();
    await client.hostReady();
    return stopwatch.elapsedMilliseconds;
  }

  /// Switches after the target passes a real DSH health check. If activation
  /// fails, reconnects the previous route with the same credentials.
  Future<bool> switchConnection(String url) async {
    final username = authUsername;
    final password = authPassword;
    final previousUrl = serverUrl;
    // Remote probes share the 10s budget of a slow cellular handshake; one
    // immediate retry rides out a single dropped handshake instead of
    // reporting a healthy server as unreachable.
    const probeTimeout = Duration(seconds: 10);
    var reachable = await probeServer(
      url,
      username: username,
      password: password,
      timeout: probeTimeout,
    );
    if (!reachable) {
      reachable = await probeServer(
        url,
        username: username,
        password: password,
        timeout: probeTimeout,
      );
    }
    if (!reachable) return false;
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
      final host = await api.hostReady();
      _hostCwd = host['cwd'] as String?;
      _api = api;
      authUsername = username;
      authPassword = password;
      _store = LocalStore();
      // Paint the cached session list and prompt counter before the network
      // refresh so cold starts render instantly.
      await _restoreLocalSnapshot();
      _streamsActive = true;
      _startStreams();
      // Enter the cached home immediately; the sidebar refresh and workspace
      // metadata can finish in the background without blocking first paint.
      unawaited(_refreshSessionsBestEffort());
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
    _saveTimer?.cancel();
    _saveTimer = null;
    _connectionController?.stop();
    unawaited(_sessionFollowSub?.cancel());
    _sessionFollowSub = null;
    _connectionController = null;
    _api?.close();
    _api = null;
    _hostCwd = null;
    unawaited(_store?.close());
    _store = null;
    authUsername = null;
    authPassword = null;
    sessions.clear();
    items.clear();
    queuedTasks.clear();
    _itemCache.clear();
    _streams.clear();
    _toolItems.clear();
    _sessionTailSeqs.clear();
    _subscribedLastSeqs.clear();
    _agentErrorNotices.clear();
    _turnErrorNotices.clear();
    approvals.clear();
    questions.clear();
    selectedSessionId = null;
    _lastLiveSeq = -1;
    _oldestSeq = 0;
    _loadingTail = false;
    _tailSyncInFlight = false;
    _gapFillInFlight = false;
    _historyGapBeforeSeq = null;
    _historyGapAfterSeq = null;
    syncingTail = false;
    fillingHistoryGap = false;
    _liveBuffer.clear();
    notifyListeners();
  }

  void _startStreams() {
    final api = _api!;
    _connectionController = SessionConnectionController(
      muxStream: api.muxStream,
      hostStream: api.hostStream,
      onMuxFrame: _onMuxFrame,
      onHostFrame: _onHostFrame,
      onStreamClosed: (_) {},
      onReconnect: _refreshSessionsIgnoringFailure,
    )..start();
  }

  void _replaceStreams() {
    _connectionController?.resume();
  }

  /// Mobile OS may suspend the sockets while the screen is locked. On resume,
  /// replace them immediately and let the mux baseline decide whether a small
  /// tail merge is needed; never clear the already cached conversation first.
  void resyncAfterResume() {
    if (!_streamsActive || _api == null) return;
    _replaceStreams();
    _refreshSessionsIgnoringFailure();
  }

  void _refreshSessionsIgnoringFailure() {
    // The cached sidebar remains usable when a background refresh fails.
    unawaited(refreshSessions().catchError((_) {}));
  }

  Future<void> _refreshSessionsBestEffort() async {
    try {
      await refreshSessions();
    } catch (_) {
      // The cached sidebar remains usable while the background refresh retries.
    }
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
      final projectionBlock = (raw['projections'] as Map?)
          ?.cast<String, dynamic>();
      final isSubagent = isSubagentSessionPayload(raw);
      if (isSubagent) {
        projections.remove(id);
        sessions.removeWhere((row) => row.sessionId == id);
        continue;
      }
      seen.add(id);
      _seedProjections(id, projectionBlock);
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
              isSubagent: isSubagent,
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
    // Archive membership and workspace grouping are owned by the workspace
    // registry, not session.list. Keep the cached state on a transient
    // failure so groups do not flash.
    try {
      final workspaceValue =
          await api.call('workspace.list', {}) as Map<String, dynamic>;
      archivedSessionIds
        ..clear()
        ..addAll(
          ((workspaceValue['archivedSessionIds'] as List?) ?? const [])
              .cast<String>(),
        );
      workspaces = ((workspaceValue['items'] as List?) ?? const [])
          .map((w) => (w as Map).cast<String, dynamic>())
          .toList();
      await _saveSessionMetadata();
    } catch (_) {
      // Session refresh remains usable when the workspace registry is down.
    }
    notifyListeners();
    unawaited(_saveSessionList());
  }

  /// Refreshes the selected session's durable subagent catalog.
  Future<void> refreshSubagents() async {
    final api = _api;
    final parentSessionId = selectedSessionId;
    if (api == null || parentSessionId == null || loadingSubagents) return;
    loadingSubagents = true;
    notifyListeners();
    try {
      final value =
          await api.call('subagent.list', {'parentSessionId': parentSessionId})
              as Map<String, dynamic>;
      if (selectedSessionId != parentSessionId) return;
      subagents = [
        for (final raw
            in (value['entries'] as List? ?? const []).whereType<Map>().map(
              (entry) => entry.cast<String, dynamic>(),
            ))
          if (raw['kind'] == 'child')
            SubagentRow(
              id: raw['id'] as String,
              mode: raw['mode'] as String,
              activity: raw['activity'] as String,
              hasChildren: raw['hasChildren'] == true,
              label: raw['label'] as String?,
            ),
      ];
    } catch (_) {
      if (selectedSessionId == parentSessionId) subagents = const [];
    } finally {
      loadingSubagents = false;
      notifyListeners();
    }
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
      _sessionTailSeqs[previous] = _lastLiveSeq;
    }
    selectedSessionId = sessionId;
    subagents = const [];
    queuedTasks.clear();
    items.clear();
    final cached = _itemCache[sessionId];
    if (cached != null) items.addAll(cached);
    _streams.clear();
    _toolItems.clear();
    _lastLiveSeq = _sessionTailSeqs[sessionId] ?? -1;
    _oldestSeq = 0;
    _loadingTail = false;
    _liveBuffer.clear();
    _historyGapBeforeSeq = null;
    _historyGapAfterSeq = null;
    fillingHistoryGap = false;
    hasMoreHistory = false;
    notifyListeners();
    final localHistory = await _loadLocalHistory(sessionId);
    if (localHistory != null) {
      hasMoreHistory = localHistory.hasMore;
      _oldestSeq = localHistory.oldestSeq ?? 0;
      _lastLiveSeq =
          _sessionTailSeqs[sessionId] ??
          localHistory.latestSeq ??
          _deriveTailSeq(localHistory.items) ??
          -1;
      if (_lastLiveSeq >= 0) _sessionTailSeqs[sessionId] = _lastLiveSeq;
    }
    if (cached == null) {
      // Cold open: paint the SQLite snapshot before the network tail arrives.
      final local = localHistory?.items ?? const <ChatItem>[];
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
    if (localHistory == null || localHistory.oldestSeq == null) {
      await loadHistory(sessionId);
    }
    final subscribedLastSeq = _subscribedLastSeqs[sessionId];
    if (subscribedLastSeq != null && subscribedLastSeq > _lastLiveSeq) {
      unawaited(syncTail(sessionId));
    }
    // Cached pages are authoritative for already loaded history; the new
    // protocol carries live Session events on a per-session follow stream.
    _startSessionFollow(sessionId);
    unawaited(refreshSubagents());
  }

  Future<_CachedHistory?> _loadLocalHistory(String sessionId) async {
    final store = _store;
    if (store == null) return null;
    try {
      final cached = await store.loadChatItems(sessionId);
      if (cached == null) return null;
      // v1 caches were a bare item list. They remain useful for instant paint,
      // but cannot safely drive the server's beforeSeq pagination cursor.
      return _CachedHistory(
        items: [for (final entry in cached.itemJsons) chatItemFromJson(entry)],
        oldestSeq: cached.oldestSeq,
        latestSeq: cached.latestSeq,
        hasMore: cached.hasMore,
      );
    } catch (_) {
      return null;
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
    // Keep every page the user has explicitly loaded. Text-heavy fields are
    // capped by chatItemToJson, while image bytes remain host-backed metadata.
    _sessionTailSeqs[sessionId] = _lastLiveSeq;
    try {
      // Map conversion is cheap and must happen on the UI isolate (ChatItem is
      // not sendable); only the expensive jsonEncode runs on a worker isolate.
      final chunkMaps = <List<Map<String, dynamic>>>[];
      for (var i = 0; i < persistable.length; i += kChatChunkSize) {
        final end = i + kChatChunkSize > persistable.length
            ? persistable.length
            : i + kChatChunkSize;
        chunkMaps.add([
          for (final item in persistable.sublist(i, end)) chatItemToJson(item),
        ]);
      }
      final oldestSeq = _oldestSeq;
      final latestSeq = _lastLiveSeq;
      final hasMore = hasMoreHistory;
      final chunkJsons = await Isolate.run(
        () => [for (final chunk in chunkMaps) jsonEncode(chunk)],
      );
      await store.saveChatItems(
        sessionId,
        chunkJsons,
        oldestSeq: oldestSeq,
        latestSeq: latestSeq,
        hasMore: hasMore,
      );
    } catch (_) {
      // Best-effort cache.
    }
  }

  void _startSessionFollow(String sessionId) {
    unawaited(_sessionFollowSub?.cancel());
    final api = _api;
    if (api == null) return;
    _sessionFollowSub = api
        .sessionFollow(sessionId)
        .listen(
          (value) {
            if (selectedSessionId != sessionId || value is! Map) return;
            final frame = value.cast<String, dynamic>();
            if (frame['type'] == 'snapshot') {
              final cursor = (frame['cursor'] as num?)?.toInt();
              if (cursor != null) _subscribedLastSeqs[sessionId] = cursor;
              _seedProjections(
                sessionId,
                (frame['projections'] as Map?)?.cast<String, dynamic>(),
              );
              return;
            }
            if (frame['type'] == 'event' && frame['event'] is Map) {
              _onMuxFrame(
                ServerFrame(
                  rpcId: mintRpcId('follow'),
                  method: 'session/event',
                  payload: {
                    'type': 'session/event',
                    'sessionId': sessionId,
                    'event': (frame['event'] as Map).cast<String, dynamic>(),
                  },
                ),
              );
            }
          },
          onError: (_) {
            if (selectedSessionId == sessionId) {
              // The next reconnect/open retries the per-session follow stream.
            }
          },
        );
  }

  /// Fetches only the newest message group after a reconnect and merges it
  /// into the local window. This keeps long conversations visible while the
  /// network catches up, instead of clearing the chat and downloading a full
  /// ten-message tail page.
  Future<void> syncTail([String? sessionId]) async {
    final api = _api;
    final target = sessionId ?? selectedSessionId;
    if (api == null ||
        target == null ||
        target != selectedSessionId ||
        _tailSyncInFlight) {
      return;
    }
    _tailSyncInFlight = true;
    syncingTail = true;
    _loadingTail = true;
    notifyListeners();
    var succeeded = false;
    final localTailBeforeSync = _lastLiveSeq;
    try {
      final value = await api.sessionHistory(target, maxMessages: 3);
      if (selectedSessionId != target) return;
      final entries = (value['events'] as List).cast<Map<String, dynamic>>();
      final incoming = <_TailItem>[];
      var maxSeq = _lastLiveSeq;
      for (final entry in entries) {
        final event = (entry['event'] as Map).cast<String, dynamic>();
        final seq = (event['seq'] as num?)?.toInt() ?? -1;
        if (seq > maxSeq) maxSeq = seq;
        _prepareTailEvent(event);
        final folded = <ChatItem>[];
        _foldEvent(event, into: folded);
        for (final item in folded) {
          incoming.add(_TailItem(item, seq));
        }
      }
      if (incoming.isNotEmpty) _mergeTailItems(incoming);
      if (entries.isNotEmpty) {
        final firstIncomingSeq =
            (((entries.first['event'] as Map)['seq']) as num).toInt();
        if (localTailBeforeSync >= 0 &&
            firstIncomingSeq > localTailBeforeSync + 1) {
          _historyGapAfterSeq = localTailBeforeSync;
          _historyGapBeforeSeq = firstIncomingSeq;
        }
      }
      if (entries.isNotEmpty && items.isNotEmpty && _oldestSeq == 0) {
        _oldestSeq = (((entries.first['event'] as Map)['seq']) as num).toInt();
      }
      _seedProjections(
        target,
        (value['projections'] as Map?)?.cast<String, dynamic>(),
      );
      final projectionSeq = ((value['projections'] as Map?)?['asOfSeq'] as num?)
          ?.toInt();
      if (projectionSeq != null && projectionSeq > maxSeq) {
        maxSeq = projectionSeq;
      }
      if (maxSeq > _lastLiveSeq) _lastLiveSeq = maxSeq;
      if (_lastLiveSeq >= 0) _sessionTailSeqs[target] = _lastLiveSeq;
      _settleOrphanedCommands();
      succeeded = true;
    } catch (_) {
      // Keep the cached conversation; the next subscribed baseline or live
      // event retries the tail merge. Buffered frames stay queued on failure.
    } finally {
      _tailSyncInFlight = false;
      syncingTail = false;
      _loadingTail = false;
      if (succeeded && _liveBuffer.isNotEmpty) {
        final buffered = List.of(_liveBuffer);
        _liveBuffer.clear();
        for (final event in buffered) {
          _foldEvent(event);
        }
      }
      _scheduleSave();
      notifyListeners();
      if (succeeded && _historyGapBeforeSeq != null) {
        unawaited(_fillHistoryGap(target));
      }
    }
  }

  /// Fills the range skipped by a tail-first reconnect after the newest
  /// messages are already visible. Pages merge by seq without moving the UI
  /// back to a loading state.
  Future<void> _fillHistoryGap(String sessionId) async {
    final api = _api;
    if (api == null || _gapFillInFlight) return;
    _gapFillInFlight = true;
    fillingHistoryGap = true;
    notifyListeners();
    var pages = 0;
    try {
      while (selectedSessionId == sessionId &&
          _historyGapBeforeSeq != null &&
          pages < 8) {
        final beforeSeq = _historyGapBeforeSeq!;
        final afterSeq = _historyGapAfterSeq ?? -1;
        final value = await api.sessionHistory(
          sessionId,
          beforeSeq: beforeSeq,
          maxMessages: 10,
        );
        if (selectedSessionId != sessionId) return;
        final entries = (value['events'] as List).cast<Map<String, dynamic>>();
        if (entries.isEmpty) {
          _historyGapBeforeSeq = null;
          _historyGapAfterSeq = null;
          break;
        }
        final firstSeq = (((entries.first['event'] as Map)['seq']) as num)
            .toInt();
        final incoming = <_TailItem>[];
        for (final entry in entries) {
          final event = (entry['event'] as Map).cast<String, dynamic>();
          final seq = (event['seq'] as num?)?.toInt() ?? -1;
          _prepareTailEvent(event);
          final folded = <ChatItem>[];
          _foldEvent(event, into: folded);
          for (final item in folded) {
            incoming.add(_TailItem(item, seq));
          }
        }
        if (incoming.isNotEmpty) _mergeTailItems(incoming);
        if (firstSeq <= afterSeq + 1) {
          _historyGapBeforeSeq = null;
          _historyGapAfterSeq = null;
          break;
        }
        _historyGapBeforeSeq = firstSeq;
        pages++;
      }
    } catch (_) {
      // Keep the gap marker; the next resume or tail repair continues it.
    } finally {
      _gapFillInFlight = false;
      fillingHistoryGap = false;
      _scheduleSave();
      notifyListeners();
    }
  }

  void _prepareTailEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (type == 'user/message') {
      final source = (data['source'] as Map?)?.cast<String, dynamic>();
      final rpcId = source?['rpcId'] as String?;
      final provisional = rpcId == null ? null : _pendingPrompts.remove(rpcId);
      if (provisional != null) items.remove(provisional);
      return;
    }
    if (type == 'assistant/message') {
      final key = '${data['turn']}:${data['step']}';
      final stream = _streams.remove(key);
      if (stream != null) items.remove(stream);
      return;
    }
    if (type == 'command/run') {
      final name = data['name'] as String? ?? '';
      final local = name.isEmpty ? null : _takeLocalCommand(name);
      if (local != null) {
        items
          ..remove(local.echo)
          ..remove(local.status);
      }
    }
  }

  int? _durableSeqOf(ChatItem item) {
    const prefixes = ['turnerr-', 'todo-', 'tr-', 'u-', 'a-', 't-'];
    for (final prefix in prefixes) {
      if (item.id.startsWith(prefix)) {
        return int.tryParse(item.id.substring(prefix.length));
      }
    }
    return null;
  }

  int? _deriveTailSeq(List<ChatItem> source) {
    int? latest;
    for (final item in source) {
      final seq = _durableSeqOf(item);
      if (seq != null && (latest == null || seq > latest)) latest = seq;
    }
    return latest;
  }

  bool _isTransientItem(ChatItem item) =>
      item.id.startsWith('local-') ||
      item.id.startsWith('stream-') ||
      item.id.startsWith('err-');

  void _preserveLoadedImages(ChatItem existing, ChatItem incoming) {
    final count = math.min(existing.images.length, incoming.images.length);
    for (var index = 0; index < count; index++) {
      incoming.images[index].data ??= existing.images[index].data;
    }
  }

  void _mergeTailItems(List<_TailItem> incoming) {
    for (final entry in incoming) {
      var existingIndex = -1;
      for (var index = 0; index < items.length; index++) {
        if (items[index].id == entry.item.id) {
          existingIndex = index;
          break;
        }
      }
      if (existingIndex >= 0) {
        _preserveLoadedImages(items[existingIndex], entry.item);
        items[existingIndex] = entry.item;
        continue;
      }
      var insertAt = items.length;
      while (insertAt > 0 && _isTransientItem(items[insertAt - 1])) {
        insertAt--;
      }
      for (var index = 0; index < insertAt; index++) {
        final seq = _durableSeqOf(items[index]);
        if (seq != null && seq > entry.seq) {
          insertAt = index;
          break;
        }
      }
      items.insert(insertAt, entry.item);
    }
    _rebuildToolIndex();
  }

  @visibleForTesting
  void mergeTailForTest(List<ChatItem> incoming, {int firstSeq = 1}) {
    _mergeTailItems([
      for (var index = 0; index < incoming.length; index++)
        _TailItem(incoming[index], firstSeq + index),
    ]);
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
      final value = await api.sessionHistory(
        sessionId,
        beforeSeq: payload['beforeSeq'] as int?,
        maxMessages: payload['maxMessages'] as int?,
      );
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
          _sessionTailSeqs[sessionId] = maxSeq;
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

  /// Recent host and turn error notices, paired by session + message so one
  /// provider failure renders once even though it arrives through two frames.
  final Map<String, ({String message, int at})> _agentErrorNotices = {};
  final Map<String, ({String message, int at})> _turnErrorNotices = {};

  bool _consumeDuplicateError(
    Map<String, ({String message, int at})> source,
    String sessionId,
    String message,
  ) {
    final existing = source[sessionId];
    if (existing == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - existing.at > 30000) {
      source.remove(sessionId);
      return false;
    }
    if (existing.message != message) return false;
    source.remove(sessionId);
    return true;
  }

  String _friendlyAgentError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('concurrent request limit')) {
      return '模型服务并发已达上限：请等待正在进行的请求结束后再试。';
    }
    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return '模型服务请求过于频繁：请稍后重试。';
    }
    if (lower.contains('insufficient') || lower.contains('quota')) {
      return '模型服务额度不足：请检查账户额度或稍后再试。';
    }
    return raw;
  }

  String? _latestRetryablePrompt() {
    for (var index = items.length - 1; index >= 0; index--) {
      final item = items[index];
      if (item.kind == ChatItemKind.user &&
          !item.provisional &&
          !item.id.startsWith('cmdin-') &&
          !item.text.trim().startsWith('/') &&
          item.images.isEmpty &&
          item.text.trim().isNotEmpty) {
        return item.text;
      }
    }
    return null;
  }

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

  /// Resolves a path to the server-owned workspace registry. The app drawer
  /// can group by cwd locally, but the web UI groups by workspace.sessionIds;
  /// only session.create(workspaceId: ...) attaches the new session there.
  Future<String?> _workspaceIdForPath(String path) async {
    final api = _api;
    if (api == null || path.isEmpty) return null;
    try {
      final value =
          await api.call('workspace.list', {}) as Map<String, dynamic>;
      for (final raw in (value['items'] as List? ?? const [])) {
        final workspace = (raw as Map).cast<String, dynamic>();
        if (workspace['path'] == path) {
          return workspace['workspaceId'] as String?;
        }
      }
    } catch (_) {
      // Workspace metadata is optional; cwd remains a safe fallback.
    }
    return null;
  }

  /// Ensures a registered workspace exists at [path] and returns its id.
  /// The server resolves an existing workspace at the same path, so this is
  /// idempotent; null means the path could not be registered (cwd fallback).
  Future<String?> _ensureWorkspaceAt(String path) async {
    final api = _api;
    if (api == null || path.isEmpty) return null;
    try {
      final value =
          await api.call('workspace.create', {'path': path})
              as Map<String, dynamic>;
      final workspace = value['workspace'] as Map?;
      return workspace?['workspaceId'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Creates a fresh session and selects it. Paths that already belong to a
  /// registered workspace are sent as workspaceId so web and app grouping
  /// agree; unregistered custom paths register a workspace first, and only a
  /// failed registration falls back to a cwd-only session.
  Future<void> createSession({String? workspaceId, String? cwd}) async {
    final api = _api;
    if (api == null) return;

    var resolvedWorkspaceId = workspaceId;
    var resolvedCwd = cwd;
    if (resolvedWorkspaceId == null) {
      final path = resolvedCwd ?? _hostCwd;
      if (path != null && path.isNotEmpty) {
        resolvedWorkspaceId = await _workspaceIdForPath(path);
        resolvedWorkspaceId ??= await _ensureWorkspaceAt(path);
        if (resolvedWorkspaceId != null) resolvedCwd = null;
      }
    }

    final payload = <String, dynamic>{
      'workspaceId': ?resolvedWorkspaceId,
      if (resolvedWorkspaceId == null) 'cwd': ?resolvedCwd,
    };
    final value =
        await api.call('session.create', payload) as Map<String, dynamic>;
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
      // Keep whatever loaded before the failure; the registry list stays
      // usable even when persistence or the refresh itself hiccups.
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
    // Best-effort: a store failure must never roll back in-memory workspace
    // or archive state that callers parsed from the server response.
    try {
      await store.kvWrite(
        'pinnedSessionIds',
        jsonEncode(pinnedSessionIds.toList()),
      );
      await store.kvWrite(
        'archivedSessionIds',
        jsonEncode(archivedSessionIds.toList()),
      );
    } catch (_) {
      // Local cache only.
    }
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
    final action = routeHostFrame(p);
    switch (action) {
      case HostSessionAdded(
        :final sessionId,
        :final isSubagent,
        :final blank,
        :final cwd,
      ):
        if (isSubagent) {
          sessions.removeWhere((row) => row.sessionId == sessionId);
          unawaited(refreshSubagents());
          return;
        }
        if (_rowOf(sessionId) == null) {
          sessions.insert(
            0,
            SessionRow(
              sessionId: sessionId,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              running: false,
              blank: blank,
              cwd: cwd,
            ),
          );
        }
      case HostSessionRemoved(:final sessionId):
        sessions.removeWhere((row) => row.sessionId == sessionId);
      case HostSessionStatus(:final sessionId, :final running):
        final row = _rowOf(sessionId);
        if (subagents.any((entry) => entry.id == sessionId)) {
          unawaited(refreshSubagents());
        }
        if (row != null) {
          row.running = running;
          if (running) {
            row.blank = false;
            row.updatedAt = DateTime.now().millisecondsSinceEpoch;
          }
        }
      case HostAgentError(:final sessionId, :final message):
        if (sessionId == selectedSessionId) {
          if (_consumeDuplicateError(_turnErrorNotices, sessionId, message)) {
            break;
          }
          _agentErrorNotices[sessionId] = (
            message: message,
            at: DateTime.now().millisecondsSinceEpoch,
          );
          items.add(
            ChatItem.notice(
              id: 'agenterr-${frame.rpcId}',
              text: _friendlyAgentError(message),
              isError: true,
              retryText: _latestRetryablePrompt(),
            ),
          );
        }
      case null:
        return;
    }
    notifyListeners();
  }

  void _onMuxFrame(ServerFrame frame) {
    final action = routeMuxFrame(frame.payload);
    switch (action) {
      case MuxSubscribed(:final sessionId, :final lastSeq):
        if (sessionId != null) {
          _subscribedLastSeqs[sessionId] = lastSeq;
          if (sessionId == selectedSessionId) {
            // The host resets the queue baseline on (re)subscription; the next
            // session/queue frame re-establishes it. An empty queue sends no
            // frame ("absence is how the client reads no tasks"), so without
            // this reset a stale snapshot would linger after a reconnect.
            queuedTasks.clear();
            if (lastSeq > _lastLiveSeq) {
              unawaited(syncTail(sessionId));
            }
          }
        }
      case MuxSessionEvent(:final sessionId, :final event):
        if (event['type'] == 'session/title' && sessionId != null) {
          final data = (event['data'] as Map).cast<String, dynamic>();
          _rowOf(sessionId)?.title = data['title'] as String?;
        }
        if (sessionId == selectedSessionId) _foldEvent(event);
      case MuxProjection(
        :final sessionId,
        :final key,
        :final seq,
        :final value,
      ):
        if (sessionId != null) {
          final table = projections.putIfAbsent(sessionId, () => {});
          final cell = table[key];
          if (cell == null || seq >= cell.seq) {
            table[key] = ProjectionCell(value, seq);
          }
          if (key == 'title') _rowOf(sessionId)?.title = value as String?;
          if (key == 'tokenUsage') _trackPetTokens(sessionId, value);
        }
      case MuxApprovalRequested(
        :final sessionId,
        :final approvalId,
        :final toolName,
        :final reason,
      ):
        if (sessionId == null) return;
        approvals.removeWhere(
          (approval) =>
              approval.rpcId == frame.rpcId ||
              approval.approvalId == approvalId,
        );
        approvals.add(
          PendingApproval(
            rpcId: frame.rpcId,
            sessionId: sessionId,
            approvalId: approvalId,
            toolName: toolName,
            reason: reason,
          ),
        );
      case MuxApprovalResolved(:final approvalId):
        approvals.removeWhere((approval) => approval.approvalId == approvalId);
      case MuxQuestionRequested(:final sessionId, :final questions):
        if (sessionId == null) return;
        this.questions.removeWhere((question) => question.rpcId == frame.rpcId);
        this.questions.add(
          PendingQuestion(
            rpcId: frame.rpcId,
            sessionId: sessionId,
            questions: questions,
          ),
        );
      case MuxQuestionResolved(:final questionRpcId):
        questions.removeWhere((question) => question.rpcId == questionRpcId);
      case MuxQueueSnapshot(:final sessionId, :final items):
        if (sessionId == selectedSessionId) {
          queuedTasks
            ..clear()
            ..addAll(parseQueuedTasks(items));
        }
      case null:
        return;
    }
    notifyListeners();
  }

  /// Test-only entry into the host-frame fold.
  @visibleForTesting
  void hostFrameForTest(ServerFrame frame) => _onHostFrame(frame);

  /// Test-only entry into the mux-frame fold.
  @visibleForTesting
  void muxFrameForTest(ServerFrame frame) => _onMuxFrame(frame);

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
    // A queued steering message retires from the transient queue once its
    // durable user/message enters the log (mirrors the host client mirror's
    // acceptDurable). queued rows are handled by the inbox-splice frames.
    if (type == 'user/message' && into == null) {
      final messageId = data['id'] as String?;
      if (messageId != null) {
        queuedTasks.removeWhere(
          (task) => task.placement == 'steering' && task.id == messageId,
        );
      }
    }
    if (into == null && _loadingTail) {
      // A history tail load clears [items] on commit; hold live events until then.
      _liveBuffer.add(event);
      return;
    }
    if (into == null && seq <= _lastLiveSeq && _lastLiveSeq >= 0) {
      return; // duplicate after reconnect
    }
    if (into == null && _lastLiveSeq >= 0 && seq > _lastLiveSeq + 1) {
      // A suspended socket left a hole. Keep the event buffered and repair the
      // tail without dropping the locally cached long conversation.
      _liveBuffer.add(event);
      unawaited(syncTail(selectedSessionId));
      return;
    }
    if (into == null) {
      _lastLiveSeq = seq;
      final sessionId = selectedSessionId;
      if (sessionId != null) _sessionTailSeqs[sessionId] = seq;
    }

    // Items appended by this fold inherit the event timestamp (drives the
    // QQ-style time dividers in the chat list).
    final targetBefore = target.length;
    final eventTime = (event['time'] as num?)?.toInt();

    final coreResult = foldCoreConversationEvent(
      type: type,
      data: data,
      seq: seq,
      target: target,
      live: into == null,
      eventTime: eventTime,
      streams: _streams,
      toolItems: _toolItems,
      pendingPrompts: _pendingPrompts,
      takeLocalCommand: (name) {
        final local = _takeLocalCommand(name);
        return local == null
            ? null
            : LocalCommandRows(
                line: local.line,
                echo: local.echo,
                status: local.status,
              );
      },
      replaceItem: _replaceItem,
      onTurnError: (raw, errorSeq) {
        final sessionId = selectedSessionId;
        if (sessionId != null &&
            _consumeDuplicateError(_agentErrorNotices, sessionId, raw)) {
          return;
        }
        if (sessionId != null) {
          _turnErrorNotices[sessionId] = (
            message: raw,
            at: DateTime.now().millisecondsSinceEpoch,
          );
        }
        items.add(
          ChatItem.notice(
            id: 'turnerr-$errorSeq',
            text: _friendlyAgentError(raw),
            isError: true,
            retryText: _latestRetryablePrompt(),
          ),
        );
      },
    );
    if (coreResult == ConversationFoldResult.stop) return;
    if (coreResult == ConversationFoldResult.handled) {
      if (eventTime != null) {
        for (var i = targetBefore; i < target.length; i++) {
          target[i].time ??= eventTime;
        }
      }
      if (into == null) _scheduleSave();
      return;
    }

    if (eventTime != null) {
      for (var i = targetBefore; i < target.length; i++) {
        target[i].time ??= eventTime;
      }
    }
    if (into == null) _scheduleSave();
  }

  int _lastLiveSeq = -1;

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
            ..images = [
              for (final raw in (json['images'] as List? ?? const []))
                ChatImage(
                  attachmentId: (raw as Map)['attachmentId'] as String,
                  mediaType: raw['mediaType'] as String,
                  bytes: (raw['bytes'] as num?)?.toInt(),
                  width: (raw['width'] as num?)?.toInt(),
                  height: (raw['height'] as num?)?.toInt(),
                  name: raw['name'] as String?,
                ),
            ]
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

/// Pure session filtering, sorting, and workspace grouping for the drawer.
///
/// Grouping mirrors the server workspace registry: registered workspaces keep
/// their server-side title and order, and sessions no workspace accounts for
/// fall back to local cwd buckets. Legacy cwd-only sessions whose cwd matches
/// a registered workspace path are displayed inside that workspace too.
library;

import 'dart:math' as math;

import '../state.dart';

enum SessionListFilter { active, running, archived, pinned }

/// One rendered drawer group.
class ProjectedGroup {
  const ProjectedGroup({
    required this.title,
    required this.rows,
    this.workspaceId,
    this.path,
  }) : isWorkspace = workspaceId != null;

  /// Server workspace id; null for local cwd buckets.
  final String? workspaceId;

  /// Display title: the workspace title, or the cwd bucket name.
  final String title;

  /// Full workspace path / bucket cwd (tooltip); null only for 未分组.
  final String? path;

  final List<SessionRow> rows;

  final bool isWorkspace;

  /// Stable collapse-persistence key.
  String get key => workspaceId != null ? 'ws:$workspaceId' : 'cwd:${path ?? ''}';
}

String _bucketName(String cwd) {
  if (cwd.isEmpty) return '未分组';
  final parts = cwd.split('/').where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? cwd : parts.last;
}

/// Filters and groups sessions. Workspace groups come first in server order;
/// cwd buckets follow by recency with the empty-cwd bucket last. Inside every
/// group the pinned-first, newest-first row order is preserved.
List<ProjectedGroup> projectSessionGroups({
  required List<SessionRow> sessions,
  required List<Map<String, dynamic>> workspaces,
  required Set<String> archivedSessionIds,
  required Set<String> pinnedSessionIds,
  required SessionListFilter filter,
}) {
  final filtered =
      sessions.where((row) {
        final archived = archivedSessionIds.contains(row.sessionId);
        return switch (filter) {
          SessionListFilter.running => !archived && row.running,
          SessionListFilter.archived => archived,
          SessionListFilter.pinned =>
            !archived && pinnedSessionIds.contains(row.sessionId),
          SessionListFilter.active => !archived,
        };
      }).toList()..sort((a, b) {
        final ap = pinnedSessionIds.contains(a.sessionId);
        final bp = pinnedSessionIds.contains(b.sessionId);
        if (ap != bp) return bp ? 1 : -1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

  // Server registry: ordered ids, title/path, membership, and path lookup.
  final wsIds = <String>[];
  final wsTitles = <String>[];
  final wsPaths = <String>[];
  final memberOf = <String, String>{};
  final wsByPath = <String, String>{};
  for (final workspace in workspaces) {
    final id = workspace['workspaceId'] as String?;
    if (id == null || id.isEmpty) continue;
    wsIds.add(id);
    wsTitles.add((workspace['title'] as String?) ?? '');
    wsPaths.add((workspace['path'] as String?) ?? '');
    for (final sessionId in (workspace['sessionIds'] as List? ?? const [])) {
      memberOf.putIfAbsent(sessionId as String, () => id);
    }
    final path = workspace['path'] as String?;
    if (path != null && path.isNotEmpty) wsByPath.putIfAbsent(path, () => id);
  }
  final wsIndex = {for (var i = 0; i < wsIds.length; i++) wsIds[i]: i};

  // Two passes keep registry members ahead of legacy cwd-matched sessions.
  final wsRows = List<List<SessionRow>?>.filled(wsIds.length, null);
  final legacyWsRows = List<List<SessionRow>?>.filled(wsIds.length, null);
  final buckets = <String, List<SessionRow>>{};
  List<SessionRow> slot(List<List<SessionRow>?> list, int index) =>
      list[index] ??= [];
  for (final row in filtered) {
    final memberId = memberOf[row.sessionId];
    if (memberId != null && wsIndex.containsKey(memberId)) {
      slot(wsRows, wsIndex[memberId]!).add(row);
    }
  }
  for (final row in filtered) {
    if (memberOf.containsKey(row.sessionId)) continue;
    final cwd = row.cwd ?? '';
    final matched = cwd.isNotEmpty ? wsByPath[cwd] : null;
    if (matched != null && wsIndex.containsKey(matched)) {
      slot(legacyWsRows, wsIndex[matched]!).add(row);
    } else {
      buckets.putIfAbsent(cwd, () => []).add(row);
    }
  }

  final groups = <ProjectedGroup>[];
  for (var i = 0; i < wsIds.length; i++) {
    final rows = [...?wsRows[i], ...?legacyWsRows[i]];
    if (rows.isEmpty) continue;
    final title = wsTitles[i].isNotEmpty
        ? wsTitles[i]
        : _bucketName(wsPaths[i]);
    groups.add(ProjectedGroup(
      title: title,
      path: wsPaths[i].isNotEmpty ? wsPaths[i] : null,
      workspaceId: wsIds[i],
      rows: rows,
    ));
  }
  final bucketKeys = buckets.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      final aTime = buckets[a]!.map((row) => row.updatedAt).fold(0, math.max);
      final bTime = buckets[b]!.map((row) => row.updatedAt).fold(0, math.max);
      return bTime.compareTo(aTime);
    });
  for (final key in bucketKeys) {
    groups.add(ProjectedGroup(
      title: _bucketName(key),
      path: key.isEmpty ? null : key,
      rows: buckets[key]!,
    ));
  }
  return groups;
}

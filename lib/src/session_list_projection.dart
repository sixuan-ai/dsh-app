/// Pure session filtering, sorting, and workspace grouping for the drawer.
library;

import 'dart:math' as math;

import '../state.dart';

enum SessionListFilter { active, running, archived, pinned }

Map<String, List<SessionRow>> projectSessionGroups({
  required List<SessionRow> sessions,
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

  final groups = <String, List<SessionRow>>{};
  for (final row in filtered) {
    groups.putIfAbsent(row.cwd ?? '', () => []).add(row);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      final aTime = groups[a]!.map((row) => row.updatedAt).fold(0, math.max);
      final bTime = groups[b]!.map((row) => row.updatedAt).fold(0, math.max);
      return bTime.compareTo(aTime);
    });
  return {for (final key in keys) key: groups[key]!};
}

import 'package:dsh_mobile/src/session_list_projection.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter_test/flutter_test.dart';

SessionRow row(
  String id, {
  int updatedAt = 0,
  bool running = false,
  String? cwd,
}) => SessionRow(
  sessionId: id,
  updatedAt: updatedAt,
  running: running,
  blank: false,
  cwd: cwd,
);

void main() {
  final sessions = [
    row('old', updatedAt: 10, cwd: '/work/a'),
    row('running', updatedAt: 20, running: true, cwd: '/work/a'),
    row('pinned', updatedAt: 5, cwd: '/work/b'),
    row('archived', updatedAt: 30),
  ];
  final archived = {'archived'};
  final pinned = {'pinned'};

  test('active projection orders workspaces and sessions by recency', () {
    final groups = projectSessionGroups(
      sessions: sessions,
      archivedSessionIds: archived,
      pinnedSessionIds: pinned,
      filter: SessionListFilter.active,
    );
    expect(groups.keys.toList(), ['/work/a', '/work/b']);
    expect(groups.values.expand((rows) => rows).map((row) => row.sessionId), [
      'running',
      'old',
      'pinned',
    ]);
  });

  test('running, archived, and pinned filters are independent', () {
    Iterable<String> ids(SessionListFilter filter) => projectSessionGroups(
      sessions: sessions,
      archivedSessionIds: archived,
      pinnedSessionIds: pinned,
      filter: filter,
    ).values.expand((rows) => rows).map((row) => row.sessionId);

    expect(ids(SessionListFilter.running), ['running']);
    expect(ids(SessionListFilter.archived), ['archived']);
    expect(ids(SessionListFilter.pinned), ['pinned']);
  });
}

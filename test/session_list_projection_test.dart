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

Map<String, dynamic> workspace(
  String id,
  String title,
  String path,
  List<String> sessionIds,
) => {
  'workspaceId': id,
  'title': title,
  'path': path,
  'sessionIds': sessionIds,
};

void main() {
  final sessions = [
    row('old', updatedAt: 10, cwd: '/work/a'),
    row('running', updatedAt: 20, running: true, cwd: '/work/a'),
    row('pinned', updatedAt: 5, cwd: '/work/b'),
    row('archived', updatedAt: 30),
  ];
  final archived = {'archived'};
  final pinned = {'pinned'};

  test('without workspaces, cwd buckets keep recency order', () {
    final groups = projectSessionGroups(
      sessions: sessions,
      workspaces: const [],
      archivedSessionIds: archived,
      pinnedSessionIds: pinned,
      filter: SessionListFilter.active,
    );
    expect(groups.map((g) => g.title), ['a', 'b']);
    expect(groups.map((g) => g.isWorkspace), everyElement(isFalse));
    expect(
      groups.expand((g) => g.rows).map((r) => r.sessionId),
      ['running', 'old', 'pinned'],
    );
    // The empty-cwd bucket is named 未分组 and sorts last.
    final ungrouped = projectSessionGroups(
      sessions: [row('archived', updatedAt: 30)],
      workspaces: const [],
      archivedSessionIds: {},
      pinnedSessionIds: {},
      filter: SessionListFilter.active,
    );
    expect(ungrouped.single.title, '未分组');
    expect(ungrouped.single.path, isNull);
  });

  test('workspace registry drives group titles, order, and membership', () {
    final groups = projectSessionGroups(
      sessions: [
        row('a1', updatedAt: 10, cwd: '/work/a'),
        row('b1', updatedAt: 20, cwd: '/work/b'),
      ],
      workspaces: [
        workspace('ws-b', '前端项目', '/work/b', ['b1']),
        workspace('ws-a', '后端项目', '/work/a', ['a1']),
      ],
      archivedSessionIds: {},
      pinnedSessionIds: {},
      filter: SessionListFilter.active,
    );
    // Server registry order wins over recency.
    expect(groups.map((g) => g.title), ['前端项目', '后端项目']);
    expect(groups.map((g) => g.workspaceId), ['ws-b', 'ws-a']);
    expect(groups.first.rows.single.sessionId, 'b1');
    expect(groups.first.key, 'ws:ws-b');
  });

  test('legacy cwd-only sessions display inside the matching workspace', () {
    final groups = projectSessionGroups(
      sessions: [
        row('member', updatedAt: 10, cwd: '/work/a'),
        row('legacy', updatedAt: 99, cwd: '/work/a'),
        row('other', updatedAt: 50, cwd: '/tmp'),
      ],
      workspaces: [workspace('ws-a', '后端项目', '/work/a', ['member'])],
      archivedSessionIds: {},
      pinnedSessionIds: {},
      filter: SessionListFilter.active,
    );
    // Registry members precede legacy matches even when newer.
    expect(groups.first.title, '后端项目');
    expect(groups.first.rows.map((r) => r.sessionId), ['member', 'legacy']);
    expect(groups.last.title, 'tmp');
    expect(groups.last.isWorkspace, isFalse);
  });

  test('running, archived, and pinned filters are independent', () {
    Iterable<String> ids(SessionListFilter filter) => projectSessionGroups(
      sessions: sessions,
      workspaces: const [],
      archivedSessionIds: archived,
      pinnedSessionIds: pinned,
      filter: filter,
    ).expand((g) => g.rows).map((r) => r.sessionId);

    expect(ids(SessionListFilter.running), ['running']);
    expect(ids(SessionListFilter.archived), ['archived']);
    expect(ids(SessionListFilter.pinned), ['pinned']);
  });

  test('pinned rows stay first inside their group', () {
    final groups = projectSessionGroups(
      sessions: [
        row('newer', updatedAt: 100, cwd: '/work/a'),
        row('pinned', updatedAt: 1, cwd: '/work/a'),
      ],
      workspaces: const [],
      archivedSessionIds: {},
      pinnedSessionIds: {'pinned'},
      filter: SessionListFilter.active,
    );
    expect(groups.single.rows.map((r) => r.sessionId), ['pinned', 'newer']);
  });
}

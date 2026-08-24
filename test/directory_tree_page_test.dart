import 'package:dsh_mobile/directory_tree_page.dart';
import 'package:dsh_mobile/src/directory_listing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DirectoryListingView listing(String path, List<DirectoryEntryView> entries) =>
    DirectoryListingView(
      path: path,
      home: '/home/x',
      crumbs: const [],
      entries: entries,
      truncated: false,
    );

DirectoryEntryView entry(String name, {bool hidden = false}) =>
    DirectoryEntryView(name: name, path: '/home/x/$name', hidden: hidden);

void main() {
  testWidgets('expands a directory level lazily and toggles hidden entries', (
    tester,
  ) async {
    final levels = <String, DirectoryListingView>{
      '': listing('/home/x', [entry('code'), entry('.config', hidden: true)]),
      '/home/x/code': listing('/home/x/code', [entry('app')]),
    };
    final requested = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryTreePage(
          directoryLoader: (path) async {
            requested.add(path);
            return levels[path ?? '']!;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('code'), findsOneWidget);
    expect(find.text('.config'), findsNothing);
    expect(find.text('app'), findsNothing);

    await tester.tap(find.text('code'));
    await tester.pump();
    expect(requested, [null, '/home/x/code']);
    expect(find.text('app'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('.config'), findsOneWidget);
  });

  testWidgets('shows error with retry when a level fails', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryTreePage(
          directoryLoader: (path) async {
            if (fail) throw StateError('权限不足');
            return listing('/home/x', [entry('code')]);
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('加载失败'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.text('code'), findsOneWidget);
  });
}

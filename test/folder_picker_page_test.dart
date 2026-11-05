import 'package:dsh_mobile/folder_picker_page.dart';
import 'package:dsh_mobile/src/directory_listing.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DirectoryEntryView entry(String name, String path, {bool hidden = false}) =>
    DirectoryEntryView(name: name, path: path, hidden: hidden);
DirectoryListingView listing(String? path) => DirectoryListingView(
  path: path ?? '/home/x',
  home: '/home/x',
  crumbs: [
    entry('/', '/'),
    entry('home', '/home'),
    entry('x', '/home/x'),
    if (path == '/home/x/code') entry('code', path!),
  ],
  entries: path == null || path == '/home/x'
      ? [
          entry('code', '/home/x/code'),
          entry('.hidden', '/home/x/.hidden', hidden: true),
        ]
      : [],
  truncated: true,
);

void main() {
  testWidgets(
    'child navigation, breadcrumbs, parent, hidden toggle and selection',
    (tester) async {
      final requested = <String?>[];
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('打开'),
                onPressed: () async {
                  picked = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FolderPickerPage(
                        directoryLoader: (path) async {
                          requested.add(path);
                          return listing(path);
                        },
                        createDirectory: (_, _) async => '/unused',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(requested, [null]);
      expect(find.text('.hidden'), findsNothing);
      expect(find.text('文件夹较多，仅显示部分结果'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('.hidden'), findsOneWidget);
      await tester.tap(find.text('code'));
      await tester.pumpAndSettle();
      expect(requested.last, '/home/x/code');
      await tester.tap(find.text('上一级'));
      await tester.pumpAndSettle();
      expect(requested.last, '/home/x');
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      expect(requested.last, '/home');
      await tester.tap(find.text('选择此文件夹'));
      await tester.pumpAndSettle();
      expect(picked, '/home');
    },
  );

  testWidgets(
    'new folder validates names, calls creator and enters returned path',
    (tester) async {
      final created = <List<String>>[];
      final requested = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FolderPickerPage(
            initialPath: '/home/x',
            directoryLoader: (path) async {
              requested.add(path);
              return listing(path);
            },
            createDirectory: (parent, name) async {
              created.add([parent, name]);
              return '/home/x/new';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, ['/home/x']);
      await tester.tap(find.byTooltip('新建文件夹'));
      await tester.pumpAndSettle();
      for (final name in ['', '.', '..', 'a/b', r'a\b']) {
        await tester.enterText(find.byType(TextFormField), name);
        await tester.tap(find.text('创建'));
        await tester.pumpAndSettle();
        expect(created, isEmpty);
        expect(
          find.text(name.isEmpty ? '请输入文件夹名称' : '名称不能是 .、.. 或包含 /、\\'),
          findsOneWidget,
        );
      }
      await tester.enterText(find.byType(TextFormField), 'new');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(created, [
        ['/home/x', 'new'],
      ]);
      expect(requested.last, '/home/x/new');
      expect(find.text('/home/x/new'), findsOneWidget);
    },
  );

  for (final code in [
    'directory-picker/unavailable',
    'directory-picker-unavailable',
  ]) {
    testWidgets('native picker guidance for $code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FolderPickerPage(
            directoryLoader: (_) async => throw DshError(code, 'native'),
            createDirectory: (_, _) async => '/unused',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(directoryBrowseUnavailableMessage), findsOneWidget);
      expect(find.text('改为手动输入路径'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  }

  testWidgets('errors retry and failed navigation cannot select stale folder', (
    tester,
  ) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPickerPage(
          directoryLoader: (path) async {
            if (path != null && fail) throw StateError('权限不足');
            return listing(path);
          },
          createDirectory: (_, _) async => '/unused',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('权限不足'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('/home/x/code'), findsOneWidget);
  });

  testWidgets('360dp width with large text has no overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: FolderPickerPage(
          directoryLoader: (path) async => listing(path),
          createDirectory: (_, _) async => '/unused',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('新建文件夹'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

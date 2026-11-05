import 'package:dsh_mobile/folder_picker_page.dart';
import 'package:dsh_mobile/new_session_sheet.dart';
import 'package:dsh_mobile/src/directory_listing.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class SheetState extends AppState {
  SheetState() {
    workspaces = [
      {
        'workspaceId': 'w1',
        'title': '项目',
        'path': '/code',
        'sessionIds': ['s1'],
      },
    ];
  }
  String? createdCwd;
  String? createdWorkspace;
  bool created = false;
  bool unavailable = false;
  @override
  Future<void> loadWorkspaces() async {}
  @override
  Future<void> createSession({String? workspaceId, String? cwd}) async {
    created = true;
    createdCwd = cwd;
    createdWorkspace = workspaceId;
  }

  @override
  Future<DirectoryListingView> listDirectory([String? path]) async {
    if (unavailable) throw DshError('directory-picker/unavailable', 'native');
    return const DirectoryListingView(
      path: '/home/x',
      home: '/home/x',
      crumbs: [],
      entries: [],
      truncated: false,
    );
  }
}

Future<void> showSheet(WidgetTester tester, SheetState state) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => NewSessionSheet(state: state),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default selected and registered workspaces always visible', (
    tester,
  ) async {
    final state = SheetState();
    addTearDown(state.dispose);
    await showSheet(tester, state);
    expect(find.text('默认工作区'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.textContaining('/code'), findsOneWidget);
    expect(find.textContaining('1 个会话'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(state.created, isTrue);
    expect(state.createdCwd, isNull);
    expect(state.createdWorkspace, isNull);
  });

  testWidgets('registered workspace can be selected', (tester) async {
    final state = SheetState();
    addTearDown(state.dispose);
    await showSheet(tester, state);
    await tester.tap(find.text('项目'));
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(state.createdWorkspace, 'w1');
  });

  testWidgets('browse pushes picker and returned path creates session', (
    tester,
  ) async {
    final state = SheetState();
    addTearDown(state.dispose);
    await showSheet(tester, state);
    await tester.tap(find.text('浏览电脑文件夹…'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderPickerPage), findsOneWidget);
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('已选择：/home/x'), findsOneWidget);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(state.createdCwd, '/home/x');
  });

  testWidgets('manual row keeps path input and validates empty path', (
    tester,
  ) async {
    final state = SheetState();
    addTearDown(state.dispose);
    await showSheet(tester, state);
    await tester.tap(find.text('手动输入路径'));
    await tester.pumpAndSettle();
    expect(find.text('必须是电脑上已存在的目录'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), ' /existing ');
    await tester.pump();
    await tester.ensureVisible(find.text('创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(state.createdCwd, '/existing');
  });

  testWidgets('unavailable picker switches sheet to manual entry', (
    tester,
  ) async {
    final state = SheetState()..unavailable = true;
    addTearDown(state.dispose);
    await showSheet(tester, state);
    await tester.tap(find.text('浏览电脑文件夹…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('改为手动输入路径'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderPickerPage), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });
}

import 'package:dsh_mobile/src/updater.dart';
import 'package:dsh_mobile/update_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders available update details and action', (tester) async {
    final info = UpdateInfo(
      version: '9.9.9',
      versionCode: 999,
      url: 'https://example.com/app.apk',
      size: 2 * 1024 * 1024,
      notes: '优化连接稳定性',
    );
    var updated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateAvailableDialog(
            info: info,
            onUpdate: () => updated = true,
          ),
        ),
      ),
    );

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v9.9.9'), findsOneWidget);
    expect(find.text('安装包 2.0 MB'), findsOneWidget);
    expect(find.text('优化连接稳定性'), findsOneWidget);
    await tester.tap(find.text('立即更新'));
    expect(updated, isTrue);
  });

  testWidgets('download dialog starts with progress state', (tester) async {
    final info = UpdateInfo(
      version: '9.9.9',
      versionCode: 999,
      url: 'https://example.com/app.apk',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateDownloadDialog(checker: UpdateChecker(), info: info),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('正在下载更新'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == '完成后将自动打开安装界面' || widget.data == '下载失败'),
      ),
      findsOneWidget,
    );
  });
}

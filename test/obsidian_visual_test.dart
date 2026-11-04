/// Native page previews with synthetic data; no device, service, or credentials.
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'package:dsh_mobile/connection_entry_view.dart';
import 'package:dsh_mobile/home_view.dart';
import 'package:dsh_mobile/session_drawer.dart';
import 'package:dsh_mobile/settings_center.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/src/ui/glass.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final render = Platform.environment['XHARNESS_RENDER_UI'] == '1';
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (render && font.existsSync()) {
      final bytes = await font.readAsBytes();
      await (FontLoader(
        'Preview Sans',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
    if (render && mono.existsSync()) {
      final bytes = await mono.readAsBytes();
      await (FontLoader(
        'monospace',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'xHarness',
      packageName: 'dev.dsh',
      version: '2.7.0',
      buildNumber: '149',
      buildSignature: '',
    );
  });
  for (final mode in ['dark', 'light', 'dark-large', 'light-large']) {
    for (final page in ['entry', 'sessions', 'chat', 'settings']) {
      testWidgets('obsidian $page $mode fits 390x844', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        });
        final old = P;
        P = paletteFor(mode.startsWith('light') ? 'light' : 'obsidian');
        addTearDown(() => P = old);
        final state = AppState()..guestAccess = true;
        final theme = ThemeController();
        final language = LanguageController();
        addTearDown(state.dispose);
        addTearDown(theme.dispose);
        addTearDown(language.dispose);
        void noop() {}
        final stamp = DateTime(2026, 11, 5, 9, 41).millisecondsSinceEpoch;
        for (final (index, title) in [
          '重构连接中心',
          '修复 OTA 下载卡 0%',
          '官网 AI 时间线',
          '语音任务让路租约',
        ].indexed) {
          state.sessions.add(
            SessionRow(
              sessionId: 's$index',
              updatedAt: stamp - index * 60000,
              running: false,
              blank: false,
              title: title,
              cwd: '/sx/xharness-app',
            ),
          );
        }
        if (page == 'sessions') {
          state.sessions[0].running = true;
          state.approvals.add(
            PendingApproval(
              rpcId: 'preview-rpc',
              sessionId: 's1',
              approvalId: 'preview-approval',
              toolName: 'bash',
            ),
          );
        }
        state.serverUrl = 'https://preview.example';
        state.connectionStatus = ServerConnectionStatus.online;
        state.projections['s2'] = {
          'plan': ProjectionCell({'active': true}, 1),
        };
        Widget drawer() => SessionDrawer(
          state: state,
          theme: theme,
          language: language,
          onLogout: noop,
          onNewSession: noop,
          onCheckUpdate: noop,
          onConnectionCenter: noop,
          connectionMode: 'public',
          localAvailable: false,
          updateAvailable: false,
          socialBaseUrl: 'https://preview.example/social',
          connectionGuideBuilder: (_) => const SizedBox(),
          changelogBuilder: (_) => const SizedBox(),
        );
        if (page == 'chat') {
          state.selectedSessionId = 's0';
          state.items.addAll([
            ChatItem.user(id: 'u1', text: '把连接中心改成整页，并保留多电脑切换。'),
            ChatItem.assistant(
              id: 'a1',
              blocks: [
                AssistantBlock(
                  'text',
                  '好的，我先读取现有的 `connection_center.dart`，再拆分页面。',
                ),
              ],
            ),
            ChatItem.tool(
                id: 't1',
                callId: 'c1',
                name: 'edit',
                arguments:
                    '{"path":"lib/connection_center.dart","oldText":"showModalBottomSheet(","newText":"Navigator.push(ConnectionCenterPage("}',
              )
              ..completed = true
              ..resultText = '已更新连接中心页面',
          ]);
        }
        final Widget content = switch (page) {
          'entry' => Scaffold(
            body: SafeArea(
              child: ConnectionEntryView(
                state: state,
                onPair: noop,
                onSettings: noop,
                onAccount: noop,
              ),
            ),
          ),
          'sessions' => Scaffold(body: drawer()),
          'settings' => SettingsCenterPage(
            language: language,
            theme: theme,
            state: state,
            socialBaseUrl: 'https://preview.example/social',
            onConnectionCenter: noop,
            onCheckUpdate: noop,
            connectionGuideBuilder: (_) => const SizedBox(),
            changelogBuilder: (_) => const SizedBox(),
          ),
          _ => HomeView(
            state: state,
            drawerBuilder: (_) => drawer(),
            onModelPicker: noop,
            onNewSession: noop,
            onRename: noop,
            onRefresh: noop,
            onRetryConnection: noop,
            onConnectionCenter: noop,
            onCheckUpdate: noop,
            onLogout: noop,
            onSuggestion: (_) {},
          ),
        };
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(P, fontFamily: render ? 'Preview Sans' : null),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(mode.endsWith('large') ? 1.6 : 1),
              ),
              child: RepaintBoundary(
                key: key,
                child: AppBackdrop(
                  enabled: mode.startsWith('dark'),
                  child: child!,
                ),
              ),
            ),
            home: content,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        if (render && mode == 'dark') {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final folder = Directory('build/ui-previews')
              ..createSync(recursive: true);
            File(
              '${folder.path}/obsidian-$page.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
        // Scroll through full content, then verify the last frame for overflow.
        if (page == 'entry' || page == 'settings') {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -1500),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

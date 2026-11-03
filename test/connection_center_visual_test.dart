import 'dart:io';
import 'dart:ui' as ui;
import 'package:dsh_mobile/connection_center.dart';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
        'Device Sans',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final mode in ['dark', 'light', 'large-offline']) {
    testWidgets(
      'connection hub renders $mode without overflow and keeps pairing reachable',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        });
        final key = GlobalKey();
        var paired = false;
        const x26 = PairedComputer(
          nodeId: 'x26-ui-fixture',
          name: 'x-26',
          localUrl: 'https://192.168.1.20:3082',
          remoteUrl: 'https://gateway.example/x26',
          fingerprint: 'ui-only',
          username: 'ui-only',
          password: 'ui-only',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: mode == 'light' ? Brightness.light : Brightness.dark,
              fontFamily: render ? 'Device Sans' : null,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  mode == 'large-offline' ? 1.6 : 1,
                ),
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: key,
              child: ConnectionCenterSheet(
                connectionMode: 'lan',
                checkingLocal: false,
                localAvailable: true,
                connected: mode != 'large-offline',
                pairedName: mode == 'large-offline'
                    ? 'x-26 办公室开发电脑与工作区'
                    : 'x-26',
                pairedComputers: const [x26],
                activePairedNodeId: x26.nodeId,
                pairedRemoteUrl: x26.remoteUrl,
                localUrl: x26.localUrl,
                computers: [
                  AccountComputer(
                    id: 'omen',
                    name: mode == 'large-offline'
                        ? 'OMEN 笔记本 · 设计与开发工作区'
                        : 'OMEN 笔记本',
                    subdomain: 'dsh.example.com',
                    isDefault: true,
                  ),
                ],
                onSwitchRemote: () {},
                onSwitchLocal: () {},
                onRefreshLocal: () {},
                onSwitchComputer: (_) {},
                onSwitchPairedComputer: (_) {},
                onPairComputer: () => paired = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.text('添加 / 管理电脑');
        expect(button, findsOneWidget);
        expect(tester.getRect(button).bottom, lessThan(824));
        if (mode == 'large-offline') {
          expect(find.text('离线'), findsOneWidget);
          expect(find.text('已连接'), findsNothing);
        }
        await tester.tap(button);
        expect(paired, isTrue);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (render) {
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final folder = Directory('build/ui-previews')
              ..createSync(recursive: true);
            File(
              '${folder.path}/connection-center-$mode.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      },
    );
  }
}

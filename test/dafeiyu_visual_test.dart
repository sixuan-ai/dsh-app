import 'dart:io';
import 'dart:ui' as ui;
import 'package:dsh_mobile/pet_page.dart';
import 'package:dsh_mobile/src/pet.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final data = await font.readAsBytes();
      await (FontLoader(
        'Device Sans',
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
    if (render) {
      final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
      if (emoji.existsSync()) {
        final bytes = await emoji.readAsBytes();
        await (FontLoader(
          'Pet Emoji',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
  for (final mode in ['adoption', 'companion', 'light', 'large']) {
    final adopted = mode != 'adoption';
    testWidgets('BigFish rice habitat $mode fits a phone', (tester) async {
      SharedPreferences.setMockInitialValues({});
      if (adopted) {
        await PetStore().save(
          Pet.newborn('大肥鱼', DateTime.now().millisecondsSinceEpoch),
        );
      }
      if (adopted) await PetTokenStore().record('preview-context', 8360000);
      final palette = paletteFor(mode == 'light' ? 'light' : 'obsidian');
      P = palette;
      addTearDown(() => P = paletteFor(kAppThemes.first.id));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(mode == 'large' ? 320 : 390, 844);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(palette).copyWith(
            textTheme: buildAppTheme(palette).textTheme.apply(
              fontFamily: render ? 'Device Sans' : null,
              fontFamilyFallback: render ? ['Pet Emoji'] : null,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(mode == 'large' ? 1.6 : 1),
            ),
            child: child!,
          ),
          home: RepaintBoundary(key: boundary, child: const PetPage()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('领养一颗神秘蛋'), findsNothing);
      if (adopted) {
        expect(find.text('1M 上下文 = 1碗白米饭'), findsOneWidget);
        expect(find.text('下一碗 36%'), findsOneWidget);
        final feed = find.byKey(const ValueKey('feed-rice'));
        if (mode != 'large') {
          expect(tester.getRect(feed).bottom, lessThanOrEqualTo(824));
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
      }
      if (render) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/ui-previews/dafeiyu-$mode.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

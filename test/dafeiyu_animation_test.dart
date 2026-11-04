import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dsh_mobile/pet_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all original animation frames decode with their original timing',
    () async {
      final manifest =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/pet/dafeiyu/provenance.json',
                ),
              )
              as Map<String, dynamic>;
      final clips = manifest['clips'] as Map<String, dynamic>;
      expect(clips.keys.toSet(), kDafeiyuClips);
      for (final entry in clips.entries) {
        final data = await rootBundle.load(dafeiyuAnimationAsset(entry.key));
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final clip = entry.value as Map<String, dynamic>;
        expect(
          codec.frameCount,
          clip['encodedFrames'] ?? clip['frames'],
          reason: entry.key,
        );
        expect(
          dafeiyuAnimationAsset(entry.key).split('/').last,
          clip['asset'] ?? '${entry.key}.webp',
        );
        var durationMs = 0;
        expect(codec.repetitionCount, clip['loop'] == true ? -1 : 0);
        for (var i = 0; i < codec.frameCount; i++) {
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 412);
          expect(frame.image.height, 344);
          durationMs += frame.duration.inMilliseconds;
          expect(
            frame.duration.inMilliseconds,
            (clip['durationsMs'] as List?)?[i] ?? clip['frameMs'],
          );
          frame.image.dispose();
        }
        expect(durationMs, (clip['frames'] as int) * (clip['frameMs'] as int));
        codec.dispose();
      }
    },
  );

  test(
    'shared search animation preserves activity names and unknown names use idle',
    () async {
      expect(
        dafeiyuAnimationAsset('working_search'),
        dafeiyuAnimationAsset('waiting'),
      );
      expect(dafeiyuAnimationAsset('missing'), dafeiyuAnimationAsset('idle'));
      expect(kDafeiyuClips.length, 16);
      expect(kDafeiyuClips.map(dafeiyuAnimationAsset).toSet().length, 15);
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final bundled = manifest
          .listAssets()
          .where(
            (path) =>
                path.startsWith('assets/pet/dafeiyu/') &&
                path.endsWith('.webp') &&
                // Static stills: reduced-motion poster and leaderboard avatar.
                !path.endsWith('/poster.webp') &&
                !path.endsWith('/avatar.webp'),
          )
          .toSet();
      expect(bundled, kDafeiyuClips.map(dafeiyuAnimationAsset).toSet());
    },
  );

  Widget sprite({
    String animation = 'idle',
    int id = 0,
    bool reduced = false,
    VoidCallback? complete,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: PetSprite(
        speciesId: 'dragon',
        stageIndex: 4,
        animation: animation,
        playbackId: id,
        onCompleted: complete,
      ),
    ),
  );

  testWidgets(
    'reduced motion uses the same BigFish poster at every growth stage',
    (tester) async {
      await tester.pumpWidget(sprite(reduced: true));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/pet/dafeiyu/poster.webp',
      );
      expect(
        find.descendant(
          of: find.byType(PetSprite),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion finishes a care action without leaving a stale activity',
    (tester) async {
      var completed = 0;
      await tester.pumpWidget(
        sprite(
          animation: 'eat_token',
          reduced: true,
          complete: () => completed++,
        ),
      );
      await tester.pump();
      expect(completed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'one-shot animation completes once and rapid clip changes can dispose safely',
    (tester) async {
      var completed = 0;
      await tester.pumpWidget(
        sprite(animation: 'dragging_release', complete: () => completed++),
      );
      for (var i = 0; i < 120 && completed == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      final rendered = tester.widget<RawImage>(
        find.descendant(
          of: find.byType(PetSprite),
          matching: find.byType(RawImage),
        ),
      );
      expect(rendered.image, isNotNull);
      expect(completed, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(completed, 1);
      for (var i = 0; i < 8; i++) {
        await tester.pumpWidget(
          sprite(animation: i.isEven ? 'head_pat' : 'eat_token', id: i),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

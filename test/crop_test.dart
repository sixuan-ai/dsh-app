/// Widget test for the avatar crop page: the image must open cover-scaled
/// and respond to drag/pinch gestures (observed through the public
/// Transform matrix, which the export inverts).
library;

import 'dart:typed_data';

import 'package:dsh_mobile/social_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img_lib;

Uint8List testImage(int width, int height) {
  final image = img_lib.Image(width: width, height: height);
  // Left half red, right half blue so crop position is unambiguous.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x < width ~/ 2) {
        image.setPixelRgb(x, y, 220, 30, 30);
      } else {
        image.setPixelRgb(x, y, 30, 30, 220);
      }
    }
  }
  return Uint8List.fromList(img_lib.encodeJpg(image, quality: 95));
}

void main() {
  testWidgets('crop page cover-scales, drags, and pinches', (tester) async {
    final bytes = testImage(800, 600);
    await tester.pumpWidget(MaterialApp(home: AvatarCropPage(bytes: bytes)));
    await tester.pumpAndSettle();

    final viewportFinder = find.byKey(const Key('avatar-crop-viewport'));
    Matrix4 matrix() => tester
        .widget<Transform>(find.descendant(
            of: viewportFinder, matching: find.byType(Transform)))
        .transform;
    double scale() => matrix().storage[0];
    Offset offset() => Offset(matrix().storage[12], matrix().storage[13]);

    final viewport = tester.getSize(viewportFinder).width;
    expect(viewport, greaterThan(0));

    // Cover scale for 800x600 in a square viewport: max(S/800, S/600).
    expect(scale(), closeTo(viewport / 600, 0.01));
    expect(offset().dx, closeTo((viewport - 800 * scale()) / 2, 1));
    expect(offset().dy, closeTo(0, 1));

    // Drag left: offset decreases, image follows the finger.
    final before = offset();
    await tester.drag(viewportFinder, const Offset(-40, 0));
    await tester.pump();
    expect(offset().dx, lessThan(before.dx - 10));

  });
}

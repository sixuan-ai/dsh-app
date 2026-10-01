import 'dart:typed_data';

import 'package:dsh_mobile/src/prompt_image_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('normalizes an image into JPEG with dimensions', () {
    final source = img.Image(width: 3, height: 2);
    source.setPixelRgb(0, 0, 255, 0, 0);
    final result = normalizePromptImage(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(result.width, 3);
    expect(result.height, 2);
    final decoded = img.decodeJpg(result.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 3);
    expect(decoded.height, 2);
  });

  test('rejects invalid image bytes', () {
    expect(
      () => normalizePromptImage(Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
  });
}

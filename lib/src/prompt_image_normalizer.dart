/// CPU-heavy prompt image decoding, orientation repair, and JPEG encoding.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

({Uint8List bytes, int width, int height}) normalizePromptImage(
  Uint8List bytes,
) {
  late final img.Image decoded;
  try {
    final value = img.decodeImage(bytes);
    if (value == null) throw StateError('无法读取图片');
    decoded = value;
  } on Object catch (error) {
    throw StateError('无法读取图片: $error');
  }
  final normalized = img.bakeOrientation(decoded);
  return (
    bytes: Uint8List.fromList(img.encodeJpg(normalized, quality: 88)),
    width: normalized.width,
    height: normalized.height,
  );
}

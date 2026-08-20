/// Regenerates launcher icons from assets/branding/hermes-agent-icon-1024.png
/// for Android (mipmap densities) and iOS (AppIcon.appiconset).
///
/// Run from the project root: dart run tool/icons.dart
library;

import 'dart:io';

import 'package:image/image.dart' as img_lib;

const _master = 'assets/branding/hermes-agent-icon-1024.png';

const _android = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

const _ios = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

void main() {
  final bytes = File(_master).readAsBytesSync();
  final master = img_lib.decodePng(bytes);
  if (master == null) {
    stderr.writeln('无法解码 $_master');
    exit(1);
  }

  for (final entry in _android.entries) {
    final out = File(
        'android/app/src/main/res/${entry.key}/ic_launcher.png');
    out.writeAsBytesSync(_resize(master, entry.value));
    stdout.writeln('${out.path} (${entry.value}px)');
  }

  for (final entry in _ios.entries) {
    final out = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}');
    out.writeAsBytesSync(_resize(master, entry.value));
    stdout.writeln('${out.path} (${entry.value}px)');
  }
}

List<int> _resize(img_lib.Image master, int size) {
  final resized = img_lib.copyResize(
    master,
    width: size,
    height: size,
    interpolation: img_lib.Interpolation.cubic,
  );
  return img_lib.encodePng(resized);
}

/// Extended integration-test driver that persists every `takeScreenshot()`
/// capture to `build/walkthrough/<name>.png`.
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final dir = Directory('build/walkthrough');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('build/walkthrough/$name.png').writeAsBytesSync(bytes);
      return true;
    },
  );
}

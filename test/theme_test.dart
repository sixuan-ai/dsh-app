/// Theme registry sanity: ids are unique, palettes resolve, and the neon
/// theme keeps its readability invariants (dark palette, dark text on the
/// bright neon accent).
library;

import 'package:dsh_mobile/src/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('old theme migrates once and subsequent choices persist', () async {
    SharedPreferences.setMockInitialValues({'themeId': 'night'});
    final first = ThemeController();
    await first.load();
    expect(first.themeId, 'obsidian');
    await first.select('light');
    final restored = ThemeController();
    await restored.load();
    expect(restored.themeId, 'light');
    expect(
      (await SharedPreferences.getInstance()).getBool('obsidianMigrationV1'),
      isTrue,
    );
    first.dispose();
    restored.dispose();
  });

  test('theme ids are unique and resolve back', () {
    final ids = kAppThemes.map((spec) => spec.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final spec in kAppThemes) {
      expect(identical(paletteFor(spec.id), spec.palette), isTrue);
    }
    expect(
      identical(paletteFor('no-such-theme'), kAppThemes.first.palette),
      isTrue,
    );
  });

  test('neon theme is dark with readable neon contrast', () {
    final neon = kAppThemes.firstWhere((spec) => spec.id == 'neon');
    expect(neon.name, '炫彩霓光');
    expect(neon.palette.isDark, isTrue);
    // Cyan→magenta gradient: the two accents must differ clearly.
    expect(neon.palette.accent, isNot(neon.palette.accent2));
    // Neon accent is bright, so labels on it are near-black.
    expect(neon.palette.onAccent.toARGB32(), lessThan(0xFF202020));
  });
}

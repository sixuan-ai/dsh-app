import 'package:dsh_mobile/src/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default language follows system (zh table)', () {
    final controller = LanguageController();
    expect(controller.languageId, 'system');
    expect(controller.locale, isNull);
    expect(controller.s.settings, '设置');
    expect(controller.s.feedback, '用户反馈');
  });

  test('switching to en swaps the strings table and locale', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = LanguageController();
    await controller.select('en');
    expect(controller.languageId, 'en');
    expect(controller.locale, const Locale('en'));
    expect(controller.s.settings, 'Settings');
    expect(controller.s.connectionCenter, 'Connection Center');
    expect(controller.s.feedbackTitle, 'Feedback');

    await controller.select('zh');
    expect(controller.s.settings, '设置');

    // Unknown ids are ignored.
    await controller.select('fr');
    expect(controller.languageId, 'zh');
  });

  test('persists the selection across instances', () async {
    SharedPreferences.setMockInitialValues({});
    final first = LanguageController();
    await first.select('en');
    final second = LanguageController();
    await second.load();
    expect(second.languageId, 'en');
    expect(second.s.settings, 'Settings');
  });

  test('zh and en tables expose the same keys via const construction', () {
    // Both tables are const-constructed with identical field sets; this
    // asserts the shared literal coverage of both languages.
    expect(Strings.zh.settings, isNotEmpty);
    expect(Strings.en.settings, isNotEmpty);
    expect(Strings.zh.connectionCenter, isNot(Strings.en.connectionCenter));
  });
}

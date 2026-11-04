import 'package:dsh_mobile/access_policy.dart';
import 'package:dsh_mobile/app_account_page.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
    'welcome explains local capabilities without requiring an account',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: AppAccountPage(state: state)));
      await tester.scrollUntilVisible(
        find.text('功能与权限'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('功能与权限'));
      await tester.pumpAndSettle();
      expect(find.text(kLocalAccessSummary), findsOneWidget);
      expect(find.textContaining(kLocalAccessLimits), findsOneWidget);
      expect(find.textContaining(kComputerPermissionSummary), findsWidgets);
      expect(find.text('无需登录 · 公网'), findsOneWidget);
      expect(find.textContaining('设备备份'), findsNothing);
      expect(find.textContaining('跨端同步'), findsNothing);
      expect(state.signedInAccount, isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'policy remains scrollable on small screens with large text $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const Scaffold(body: AccessPolicySheet()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('我知道了'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

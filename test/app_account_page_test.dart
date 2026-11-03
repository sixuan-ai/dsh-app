import 'dart:io';
import 'dart:ui' as ui;
import 'package:dsh_mobile/app_account_page.dart';
import 'package:dsh_mobile/connection_center.dart';
import 'package:dsh_mobile/connection_entry_view.dart';
import 'package:dsh_mobile/src/sixuan_account.dart';
import 'package:dsh_mobile/state.dart';
import 'package:dsh_mobile/main.dart' show DshApp, HomePage;
import 'package:dsh_mobile/home_view.dart';
import 'package:dsh_mobile/src/connector_pairing.dart';
import 'package:dsh_mobile/src/protocol.dart' show AccountComputer;
import 'package:dsh_mobile/src/theme.dart' show ThemeController;
import 'package:dsh_mobile/src/l10n.dart' show LanguageController;
import 'app_entry_test.dart' show RouteState, computer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FormApi extends SixuanAccountApi {
  String? requested, verified, newPassword;
  int passwordLoginCalls = 0;
  bool rejectPassword = false;
  @override
  Future<Map<String, dynamic>> passwordLogin({
    required String email,
    required String password,
    required String deviceId,
    bool remember = false,
  }) async {
    passwordLoginCalls++;
    if (rejectPassword) throw const SixuanAccountError('邮箱或密码错误', status: 401);
    return {
      'access_token': 't' * 43,
      'user': {'email': email, 'display_name': 'Fixture'},
    };
  }

  @override
  Future<Map<String, dynamic>> requestCode({
    required String mode,
    required String email,
    required String password,
    required String name,
    required String deviceId,
  }) async {
    requested = mode;
    return {'secret': 'fixture-challenge'};
  }

  @override
  Future<Map<String, dynamic>> verifyCode({
    required String mode,
    required String secret,
    required String code,
    required String deviceId,
    bool remember = false,
    String? password,
  }) async {
    verified = mode;
    newPassword = password;
    return mode == 'login'
        ? {
            'access_token': 't' * 43,
            'user': {'email': 'fixture@example.com', 'display_name': 'Fixture'},
          }
        : {'ok': true};
  }
}

Widget app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: Platform.environment['XHARNESS_RENDER_UI'] == '1'
        ? 'Device Sans'
        : null,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
Finder field(String label) => find.widgetWithText(TextFormField, label);
Future<void> tap(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  setUpAll(() async {
    if (Platform.environment['XHARNESS_RENDER_UI'] != '1') return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final bytes = await File(
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ).readAsBytes();
    await (FontLoader(
      'Device Sans',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  testWidgets('skip login enters local-only mode without an account request', (
    tester,
  ) async {
    final api = FormApi();
    final state = AppState(identityApi: api);
    addTearDown(state.dispose);
    var completed = false;
    await tester.pumpWidget(
      app(AppAccountPage(state: state, onCompleted: () => completed = true)),
    );
    await tap(tester, '不登录，先连接');
    expect(completed, isTrue);
    expect(state.guestAccess, isTrue);
    expect(api.requested, isNull);
  });
  testWidgets(
    'fresh app reaches connection home after skipping account login',
    (tester) async {
      await tester.pumpWidget(const DshApp());
      await tester.pumpAndSettle();
      expect(find.text('不登录，先连接'), findsOneWidget);
      await tap(tester, '不登录，先连接');
      expect(find.text('配对我的电脑'), findsOneWidget);
      expect(find.text('局域网模式 · 未登录'), findsOneWidget);
      expect(find.text('验证你的邮箱'), findsNothing);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  for (final mode in [
    AppAccountMode.login,
    AppAccountMode.register,
    AppAccountMode.recover,
  ]) {
    testWidgets(
      'native ${mode.name} completes the requested authentication flow',
      (tester) async {
        final api = FormApi();
        final state = AppState(identityApi: api);
        addTearDown(state.dispose);
        var completed = false;
        await tester.pumpWidget(
          app(
            AppAccountPage(
              state: state,
              initialMode: mode,
              onCompleted: () => completed = true,
            ),
          ),
        );
        await tester.enterText(field('邮箱'), 'fixture@example.com');
        if (mode != AppAccountMode.recover) {
          await tester.enterText(field('密码'), 'fixture-password');
        }
        if (mode == AppAccountMode.register) {
          await tester.enterText(field('确认密码'), 'fixture-password');
        }
        if (mode == AppAccountMode.login) {
          await tap(tester, '登录');
          expect(api.passwordLoginCalls, 1);
          expect(api.requested, isNull);
          expect(api.verified, isNull);
          expect(find.text('六位邮件验证码'), findsNothing);
          expect(completed, isTrue);
          expect(state.signedInAccount?.email, 'fixture@example.com');
          expect(state.canUsePublicConnection, isTrue);
          await tester.pumpWidget(const SizedBox());
          return;
        }
        await tap(tester, '获取邮件验证码');
        expect(api.requested, mode.name);
        expect(find.text('验证你的邮箱'), findsOneWidget);
        await tester.enterText(field('六位邮件验证码'), '123456');
        if (mode == AppAccountMode.recover) {
          await tester.enterText(field('新密码'), 'replacement-password');
          await tester.enterText(field('确认新密码'), 'replacement-password');
        }
        await tap(
          tester,
          mode == AppAccountMode.login
              ? '验证并登录'
              : mode == AppAccountMode.register
              ? '验证并创建账号'
              : '验证并重置密码',
        );
        expect(api.verified, mode.name);
        if (mode == AppAccountMode.login) {
          expect(completed, isTrue);
          expect(state.signedInAccount?.email, 'fixture@example.com');
          expect(state.canUsePublicConnection, isTrue);
        } else {
          expect(completed, isFalse);
          expect(state.signedInAccount, isNull);
          expect(find.text('继续登录'), findsOneWidget);
          if (mode == AppAccountMode.recover) {
            expect(api.newPassword, 'replacement-password');
          }
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'guest connection page opens pairing and offers account upgrade',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.enterGuestMode();
      var pairing = 0, account = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ConnectionEntryView(
              state: state,
              onPair: () => pairing++,
              onAccount: () => account++,
              onSettings: () {},
            ),
          ),
        ),
      );
      await tap(tester, '局域网直连');
      await tap(tester, '登录后使用公网连接');
      expect(pairing, 1);
      expect(account, 1);
    },
  );
  testWidgets(
    'wrong password can be retried without requesting mail or leaving LAN mode',
    (tester) async {
      final api = FormApi()..rejectPassword = true;
      final state = AppState(identityApi: api);
      addTearDown(state.dispose);
      await state.enterGuestMode();
      await tester.pumpWidget(
        app(AppAccountPage(state: state, initialMode: AppAccountMode.login)),
      );
      await tester.enterText(field('邮箱'), 'fixture@example.com');
      await tester.enterText(field('密码'), 'fixture-password');
      await tap(tester, '登录');
      expect(find.text('邮箱或密码错误'), findsOneWidget);
      expect(api.requested, isNull);
      expect(state.guestAccess, isTrue);
      expect(state.signedInAccount, isNull);
      api.rejectPassword = false;
      await tap(tester, '登录');
      expect(api.passwordLoginCalls, 2);
      expect(state.signedInAccount?.email, 'fixture@example.com');
      expect(state.canUsePublicConnection, isTrue);
    },
  );
  testWidgets(
    'account inputs request the soft keyboard again after it was hidden',
    (tester) async {
      final state = AppState(identityApi: FormApi());
      addTearDown(state.dispose);
      await tester.pumpWidget(
        app(AppAccountPage(state: state, initialMode: AppAccountMode.login)),
      );
      await tester.tap(field('邮箱'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.testTextInput.setClientArgs?['inputType']['name'],
        'TextInputType.text',
      );
      expect(tester.testTextInput.setClientArgs?['enableSuggestions'], isFalse);
      expect(tester.testTextInput.setClientArgs?['autocorrect'], isFalse);
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(field('邮箱'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(field('密码'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.testTextInput.setClientArgs?['obscureText'], isTrue);
    },
  );
  testWidgets(
    'guest public control opens login rather than switching transport',
    (tester) async {
      var account = 0, route = 0;
      await tester.pumpWidget(
        app(
          ConnectionCenterSheet(
            connectionMode: 'lan',
            checkingLocal: false,
            localAvailable: true,
            publicAccessAllowed: false,
            onAccount: () => account++,
            onSwitchRemote: () => route++,
            onSwitchLocal: () {},
            onRefreshLocal: () {},
          ),
        ),
      );
      await tap(tester, '登录后使用');
      expect(account, 1);
      expect(route, 0);
    },
  );
  testWidgets('legacy logout callback preserves paired and account computers', (
    tester,
  ) async {
    final state = RouteState();
    final theme = ThemeController();
    final language = LanguageController();
    addTearDown(state.dispose);
    addTearDown(theme.dispose);
    addTearDown(language.dispose);
    await ConnectorStore().save(computer);
    await state.restorePairedComputers();
    final omen = AccountComputer(
      id: 'legacy-omen',
      name: 'OMEN 笔记本',
      subdomain: 'dsh.example.com',
      isDefault: true,
    );
    state.computers.add(omen);
    state.serverUrl = computer.remoteUrl!;
    state.authUsername = computer.username;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quickStartShown', true);
    await tester.pumpWidget(
      app(HomePage(state: state, theme: theme, language: language)),
    );
    await tester.pumpAndSettle();
    tester.widget<HomeView>(find.byType(HomeView)).onLogout();
    await tester.pumpAndSettle();
    expect(state.signedInAccount, isNull);
    expect(state.guestAccess, isTrue);
    expect(state.canUsePublicConnection, isFalse);
    expect((await ConnectorStore().load())?.nodeId, computer.nodeId);
    expect(state.savedPairedComputers.single.nodeId, computer.nodeId);
    expect(state.computers.any((c) => c.id == omen.id), isTrue);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final width in [320.0, 390.0]) {
    for (final mode in [AppAccountMode.welcome, AppAccountMode.login]) {
      for (final dark in [false, true]) {
        testWidgets('${mode.name} renders at $width dark=$dark', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = AppState();
          addTearDown(state.dispose);
          final key = GlobalKey();
          await tester.pumpWidget(
            app(
              RepaintBoundary(
                key: key,
                child: AppAccountPage(state: state, initialMode: mode),
              ),
              brightness: dark ? Brightness.dark : Brightness.light,
              scale: width == 320 ? 1.5 : 1,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (Platform.environment['XHARNESS_RENDER_UI'] == '1' &&
              width == 390) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/reports/account-${mode.name}-${dark ? 'dark' : 'light'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}

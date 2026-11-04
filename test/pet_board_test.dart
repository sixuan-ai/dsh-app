import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dsh_mobile/pet_board_page.dart';
import 'package:dsh_mobile/src/pet_board.dart';
import 'package:dsh_mobile/src/sixuan_account.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/src/ui/glass.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixture({bool mine = true}) => {
  'scope': 'all',
  'weekKey': '2026-11-02',
  'items': [
    for (var i = 0; i < 8; i++)
      {
        'rank': i + 1,
        'nickname': ['荧光小鱼', '星河', '橘子海', '云端伙伴'][i % 4],
        'petName': '大肥鱼',
        'species': 'dafeiyu',
        'tokens': 24000000 - i * 2000000,
        'score': 6000000 - i * 500000,
        'level': 25 - i * 2,
        'stage': '灵魂搭档',
        'pkScore': 1400,
      },
  ],
  if (mine)
    'me': {
      'rank': 128,
      'nickname': '小鱼',
      'tokens': 1000000,
      'gap': 200000,
      'optedOut': false,
    },
};

class PreviewState extends AppState {
  bool authenticated = true;
  @override
  String? get petBoardToken => authenticated ? 'synthetic-session' : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final render = Platform.environment['XHARNESS_RENDER_UI'] == '1';
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final file = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (render && file.existsSync()) {
      await (FontLoader('Preview Sans')..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          ))
          .load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('models parse outside-top100 and absent me', () {
    final data = PetBoardData.fromJson(fixture());
    expect(data.items.first.level, 25);
    expect(data.me!.rank, 128);
    expect(data.me!.gap, 200000);
    expect(PetBoardData.fromJson(fixture(mine: false)).me, isNull);
    expect(
      PetBoardEntry.fromJson({'nickname': 'fish', 'optedOut': true}).optedOut,
      isTrue,
    );
  });
  test('API uses current session and rejects guest writes', () async {
    String? token = 'first';
    final seen = <http.Request>[];
    final api = PetBoardApi(
      token: () => token,
      client: MockClient((r) async {
        seen.add(r);
        return http.Response(
          jsonEncode(fixture()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await api.board();
    expect(seen.last.headers['Authorization'], 'Bearer first');
    token = null;
    await api.board();
    expect(seen.last.headers.containsKey('Authorization'), isFalse);
    await expectLater(api.report({'tokens': 1}), throwsStateError);
    expect(seen.length, 2);
  });
  test(
    'participation setting preserves an unchanged masked nickname',
    () async {
      late Map<String, dynamic> submitted;
      final api = PetBoardApi(
        token: () => 'synthetic',
        client: MockClient((request) async {
          submitted = (jsonDecode(request.body) as Map).cast<String, dynamic>();
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      await api.settings(null, true);
      expect(submitted, {'optedOut': true});
    },
  );
  testWidgets('reporter debounce, resume throttle and cancellation', (
    tester,
  ) async {
    var now = DateTime(2026);
    var calls = 0;
    final reporter = PetBoardReporter(
      send: () async {
        calls++;
      },
      clock: () => now,
    );
    addTearDown(reporter.dispose);
    reporter.changed();
    await tester.pump(const Duration(seconds: 31));
    expect(calls, 0);
    reporter.setActive(true);
    reporter.changed();
    await tester.pump(const Duration(seconds: 20));
    now = now.add(const Duration(seconds: 20));
    reporter.changed();
    await tester.pump(const Duration(seconds: 29));
    now = now.add(const Duration(seconds: 29));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 1));
    expect(calls, 1);
    now = now.add(const Duration(minutes: 1));
    reporter.resumed();
    await tester.pump();
    expect(calls, 2);
    now = now.add(const Duration(minutes: 9));
    reporter.resumed();
    await tester.pump();
    expect(calls, 2);
    now = now.add(const Duration(minutes: 1));
    reporter.resumed();
    await tester.pump();
    expect(calls, 3);
    reporter.changed();
    reporter.setActive(false);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 3);
  });
  testWidgets('silent failure retries and logout cancels retry', (
    tester,
  ) async {
    var calls = 0;
    var now = DateTime(2026);
    final reporter = PetBoardReporter(
      clock: () => now,
      send: () async {
        calls++;
        throw StateError('offline');
      },
    );
    addTearDown(reporter.dispose);
    reporter.setActive(true);
    reporter.opened();
    await tester.pump();
    expect(calls, 1);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
    reporter.setActive(false);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 2);
  });
  test('restored unverified identity cannot supply a bearer', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.signedInAccount = SixuanSession(
      token: 't' * 43,
      email: 'fake@example.com',
      name: 'fake',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(state.petBoardToken, isNull);
  });

  Future<void> mount(
    WidgetTester tester, {
    required PetBoardApi api,
    AppState? state,
    VoidCallback? login,
    double scale = 1,
    GlobalKey? boundary,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(P, fontFamily: render ? 'Preview Sans' : null),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: boundary,
            child: AppBackdrop(enabled: P.isDark, child: child!),
          ),
        ),
        home: PetBoardPage(api: api, state: state, onLogin: login),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'reporter respects minimum interval and serializes in-flight reports',
    (tester) async {
      var now = DateTime(2026);
      var calls = 0;
      var finished = Completer<void>();
      final reporter = PetBoardReporter(
        clock: () => now,
        send: () {
          calls++;
          return finished.future;
        },
      );
      addTearDown(reporter.dispose);
      reporter.setActive(true);
      reporter.opened();
      reporter.opened();
      await tester.pump();
      expect(calls, 1);
      finished.complete();
      await tester.pump();
      now = now.add(const Duration(seconds: 10));
      reporter.opened();
      await tester.pump(const Duration(seconds: 9));
      expect(calls, 1);
      now = now.add(const Duration(seconds: 10));
      finished = Completer<void>()..complete();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    },
  );
  test(
    'logout immediately invalidates bearer before storage finishes',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.acceptAccountSession(
        SixuanSession(
          token: 't' * 43,
          email: 'fake@example.com',
          name: 'fake',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      expect(state.petBoardToken, isNotNull);
      final logout = state.enterGuestMode();
      expect(state.petBoardToken, isNull);
      await logout;
    },
  );
  testWidgets('guest login guide and scope request', (tester) async {
    var loggedIn = false;
    final scopes = <String?>[];
    final api = PetBoardApi(
      token: () => null,
      client: MockClient((r) async {
        scopes.add(r.url.queryParameters['scope']);
        return http.Response(
          jsonEncode(fixture(mine: false)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await mount(tester, api: api, login: () => loggedIn = true);
    expect(find.text('登录后上榜'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-pet-rank')), findsNothing);
    await tester.tap(find.text('前往登录'));
    expect(loggedIn, isTrue);
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(scopes, ['all', 'week']);
  });
  testWidgets('authenticated rank card and settings submission', (
    tester,
  ) async {
    final state = PreviewState();
    addTearDown(state.dispose);
    Map<String, dynamic>? settings;
    final api = PetBoardApi(
      token: () => state.petBoardToken,
      client: MockClient((r) async {
        if (r.method == 'PATCH') {
          settings = (jsonDecode(r.body) as Map).cast<String, dynamic>();
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode(fixture()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await mount(tester, api: api, state: state);
    expect(find.text('我的排名 · #128'), findsOneWidget);
    expect(find.text('距前一名 200.0K token'), findsOneWidget);
    await tester.tap(find.byTooltip('排行榜设置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('board-nickname')), '新昵称');
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings, {'nickname': '新昵称', 'optedOut': true});
    await tester.pump(const Duration(seconds: 2));
    state.authenticated = false;
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('登录后上榜'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('error can retry then show empty board', (tester) async {
    var fail = true;
    final api = PetBoardApi(
      token: () => null,
      client: MockClient(
        (r) async =>
            http.Response(fail ? '{}' : '{"items":[]}', fail ? 503 : 200),
      ),
    );
    addTearDown(api.close);
    await mount(tester, api: api);
    expect(find.text('暂时无法加载排行榜，请稍后重试'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有伙伴上榜，成为第一个吧！'), findsOneWidget);
  });
  for (final mode in ['dark', 'light', 'dark-large', 'light-large']) {
    for (final guest in [false, true]) {
      testWidgets('visual pet board $mode guest=$guest 390x844', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final old = P;
        P = paletteFor(mode.startsWith('light') ? 'light' : 'obsidian');
        addTearDown(() => P = old);
        final state = PreviewState()..authenticated = !guest;
        addTearDown(state.dispose);
        final api = PetBoardApi(
          token: () => state.petBoardToken,
          client: MockClient(
            (r) async => http.Response(
              jsonEncode(fixture(mine: !guest)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        addTearDown(api.close);
        final key = GlobalKey();
        await mount(
          tester,
          api: api,
          state: state,
          scale: mode.endsWith('large') ? 1.6 : 1,
          boundary: key,
        );
        expect(tester.takeException(), isNull);
        if (render && mode == 'dark') {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            Directory('build/ui-previews').createSync(recursive: true);
            File(
              'build/ui-previews/pet-board-${guest ? 'guest' : 'all'}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1400),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

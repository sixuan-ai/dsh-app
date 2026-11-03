import 'dart:convert';
import 'package:dsh_mobile/src/sixuan_account.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

SixuanSession session({String email = 'fixture@example.com'}) => SixuanSession(
  token: 't' * 43,
  email: email,
  name: 'Fixture',
  expiresAt: DateTime.now().add(const Duration(hours: 12)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('native password sign-in does not request an email code', () async {
    final requests = <http.Request>[];
    final api = SixuanAccountApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"type":"access_token"}', 200);
      }),
    );
    addTearDown(api.close);
    await api.passwordLogin(
      email: 'fixture@example.com',
      password: 'fixture-password',
      deviceId: 'device',
      remember: true,
    );
    expect(requests, hasLength(1));
    expect(
      requests.single.url.toString(),
      '$kSixuanAccountsOrigin/api/app/login',
    );
    expect(jsonDecode(requests.single.body), {
      'email': 'fixture@example.com',
      'password': 'fixture-password',
      'uuid': 'device',
      'autoLogin': true,
    });
  });
  test(
    'native email flows use the existing HTTPS account API contract',
    () async {
      final requests = <http.Request>[];
      final api = SixuanAccountApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      addTearDown(api.close);
      for (final mode in ['login', 'register', 'recover']) {
        await api.requestCode(
          mode: mode,
          email: 'fixture@example.com',
          password: 'fixture-password',
          name: 'Fixture',
          deviceId: 'device',
        );
        await api.verifyCode(
          mode: mode,
          secret: 'challenge',
          code: '123456',
          deviceId: 'device',
          remember: true,
          password: 'replacement-password',
        );
      }
      expect(requests.map((r) => r.url.path).toList(), [
        '/api/login',
        '/api/login',
        '/api/register',
        '/api/register/verify',
        '/api/password-reset/request',
        '/api/password-reset/confirm',
      ]);
      for (final request in requests) {
        expect(request.url.origin, kSixuanAccountsOrigin);
        expect(request.method, 'POST');
        expect(request.headers.containsKey('authorization'), isFalse);
      }
      expect(jsonDecode(requests[0].body)['type'], 'account');
      expect(
        jsonDecode(requests[1].body),
        containsPair('verificationCode', '123456'),
      );
      expect(jsonDecode(requests[1].body), containsPair('autoLogin', true));
      expect(jsonDecode(requests[4].body), {
        'email': 'fixture@example.com',
        'uuid': 'device',
      });
      expect(jsonDecode(requests[5].body)['password'], 'replacement-password');
    },
  );
  test(
    'session creation, validation and logout reuse the bearer token',
    () async {
      final requests = <http.Request>[];
      final api = SixuanAccountApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(api.close);
      final value = api.sessionFromResult({
        'access_token': 't' * 43,
        'user': {'email': 'fixture@example.com', 'display_name': 'Fixture'},
      }, remember: true);
      expect(value.expiresAt.difference(DateTime.now()).inHours, 167);
      await api.validate(value);
      await api.logout(value);
      expect(requests.map((r) => r.method), ['GET', 'POST']);
      expect(requests.map((r) => r.url.path), [
        '/api/currentUser',
        '/api/logout',
      ]);
      expect(
        requests.every(
          (r) => r.headers['authorization'] == 'Bearer ${value.token}',
        ),
        isTrue,
      );
    },
  );
  test(
    'authentication errors retain status and do not include request secrets',
    () async {
      final api = SixuanAccountApi(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"请先登录"}',
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.validate(session()),
        throwsA(
          isA<SixuanAccountError>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.toString(), 'message', '请先登录'),
        ),
      );
    },
  );
  test(
    'encrypted account storage persists session only, handles concurrent clear',
    () async {
      final store = SixuanAccountStore();
      await store.save(session());
      expect((await store.load())?.email, 'fixture@example.com');
      final raw = await const FlutterSecureStorage().read(
        key: SixuanAccountStore.key,
      );
      expect((jsonDecode(raw!) as Map).keys.toSet(), {
        'token',
        'email',
        'name',
        'expiresAt',
      });
      await Future.wait([store.save(session()), store.clear()]);
      expect(await store.load(), isNull);
    },
  );
  test(
    'expired or malformed stored sessions cannot restore account access',
    () async {
      final store = SixuanAccountStore();
      for (final value in [
        'broken',
        '{}',
        '{"token":123}',
        jsonEncode({...session().toJson(), 'expiresAt': 1}),
      ]) {
        await const FlutterSecureStorage().write(
          key: SixuanAccountStore.key,
          value: value,
        );
        expect(await store.load(), isNull);
        expect(
          await const FlutterSecureStorage().read(key: SixuanAccountStore.key),
          isNull,
        );
      }
    },
  );
}

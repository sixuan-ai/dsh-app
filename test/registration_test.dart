/// 注册流程的协议层测试:验证码请求、校验、以及各类失败的映射。
///
/// 用一个真实的本地 HTTP 服务替代远端,确保请求体/路径/错误码与
/// `server/registration/dsh-register.py` 的约定一致。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dsh_mobile/src/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for the registration endpoints.
class _FakeDirectory {
  _FakeDirectory(this._handler);

  final Map<String, dynamic> Function(String path, Map<String, dynamic> body)
      _handler;
  late final HttpServer _server;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      final body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final result = _handler(request.uri.path, body);
      request.response
        ..statusCode = result['status'] as int
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(result['body']));
      await request.response.close();
    });
    return 'http://127.0.0.1:${_server.port}';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  test('config is parsed into domains, policy and mail state', () async {
    final fake = _FakeDirectory((path, _) {
      expect(path, '/directory/register/config');
      return {
        'status': 200,
        'body': {
          'ok': true,
          'domains': ['corp.com'],
          'minPassword': 10,
          'mailEnabled': true,
        },
      };
    });
    final base = await fake.start();
    try {
      final config = await fetchRegistrationConfig(base);
      expect(config.domains, ['corp.com']);
      expect(config.minPassword, 10);
      expect(config.mailEnabled, isTrue);
    } finally {
      await fake.stop();
    }
  });

  test('request posts the mailbox and reports success', () async {
    final seen = <String, dynamic>{};
    final fake = _FakeDirectory((path, body) {
      expect(path, '/directory/register/request');
      seen.addAll(body);
      return {
        'status': 200,
        'body': {'ok': true, 'expiresIn': 600},
      };
    });
    final base = await fake.start();
    try {
      await requestRegistrationCode(base, 'zhang@corp.com');
      expect(seen['email'], 'zhang@corp.com');
    } finally {
      await fake.stop();
    }
  });

  test('a rejected domain surfaces the server code and message', () async {
    final fake = _FakeDirectory((_, _) => {
          'status': 400,
          'body': {
            'ok': false,
            'error': 'email-not-allowed',
            'message': '请使用公司企业邮箱',
          },
        });
    final base = await fake.start();
    try {
      await expectLater(
        requestRegistrationCode(base, 'someone@gmail.com'),
        throwsA(isA<DshError>()
            .having((e) => e.code, 'code', 'email-not-allowed')
            .having((e) => e.message, 'message', '请使用公司企业邮箱')),
      );
    } finally {
      await fake.stop();
    }
  });

  test('the resend cooldown is surfaced with its wait', () async {
    final fake = _FakeDirectory((_, _) => {
          'status': 429,
          'body': {
            'ok': false,
            'error': 'too-soon',
            'message': '请 42 秒后再试',
          },
        });
    final base = await fake.start();
    try {
      await expectLater(
        requestRegistrationCode(base, 'zhang@corp.com'),
        throwsA(isA<DshError>()
            .having((e) => e.code, 'code', 'too-soon')
            .having((e) => e.message, 'message', contains('42'))),
      );
    } finally {
      await fake.stop();
    }
  });

  test('verify returns the login name and provisioning state', () async {
    final seen = <String, dynamic>{};
    final fake = _FakeDirectory((path, body) {
      expect(path, '/directory/register/verify');
      seen.addAll(body);
      return {
        'status': 200,
        'body': {
          'ok': true,
          'username': 'zhang',
          'provisioned': false,
          'message': '账号已创建,等待管理员开通实例',
        },
      };
    });
    final base = await fake.start();
    try {
      final result = await verifyRegistrationCode(
        base,
        email: 'zhang@corp.com',
        code: '123456',
        password: 'StrongPass123',
      );
      expect(seen['code'], '123456');
      expect(seen['password'], 'StrongPass123');
      expect(result.username, 'zhang');
      // An instance is not part of sign-up; the UI must say so rather than
      // implying the account is ready to connect.
      expect(result.provisioned, isFalse);
      expect(result.message, contains('开通实例'));
    } finally {
      await fake.stop();
    }
  });

  test('a wrong code reports the remaining attempts', () async {
    final fake = _FakeDirectory((_, _) => {
          'status': 400,
          'body': {
            'ok': false,
            'error': 'code-wrong',
            'message': '验证码不正确,还可尝试 3 次',
          },
        });
    final base = await fake.start();
    try {
      await expectLater(
        verifyRegistrationCode(
          base,
          email: 'zhang@corp.com',
          code: '000000',
          password: 'StrongPass123',
        ),
        throwsA(isA<DshError>()
            .having((e) => e.code, 'code', 'code-wrong')
            .having((e) => e.message, 'message', contains('3'))),
      );
    } finally {
      await fake.stop();
    }
  });

  test('an unprovisioned login is distinct from bad credentials', () async {
    // The directory answers 403 not-provisioned for a correct password whose
    // account has no instance; treating that as "wrong password" would send
    // the user chasing the wrong problem.
    final fake = _FakeDirectory((path, _) {
      expect(path, '/directory/login');
      return {
        'status': 403,
        'body': {
          'ok': false,
          'error': 'not-provisioned',
          'message': '账号已创建,等待管理员开通实例',
        },
      };
    });
    final base = await fake.start();
    try {
      await expectLater(
        directoryLogin(base, 'zhang', 'StrongPass123'),
        throwsA(isA<DshError>()
            .having((e) => e.code, 'code', 'directory-not-provisioned')),
      );
    } finally {
      await fake.stop();
    }
  });

  test('a provisioned login resolves to the instance URL', () async {
    final fake = _FakeDirectory((_, _) => {
          'status': 200,
          'body': {'ok': true, 'username': 'zhang', 'server': 'zhang.corp.com'},
        });
    final base = await fake.start();
    try {
      final result = await directoryLogin(base, 'zhang', 'StrongPass123');
      expect(result.defaultUrl, 'https://zhang.corp.com');
      // A bare `server` response folds into a single machine for compatibility.
      expect(result.computers, hasLength(1));
      expect(result.computers.single.subdomain, 'zhang.corp.com');
    } finally {
      await fake.stop();
    }
  });

  test('a multi-computer login returns every machine and the default', () async {
    final fake = _FakeDirectory((_, _) => {
          'status': 200,
          'body': {
            'ok': true,
            'username': 'zhang',
            'server': 'omen.corp.com',
            'computers': [
              {
                'id': 'omen',
                'name': 'OMEN',
                'subdomain': 'omen.corp.com',
                'default': true,
              },
              {
                'id': 'mac',
                'name': 'MacBook',
                'subdomain': 'mac.corp.com',
                'default': false,
              },
            ],
          },
        });
    final base = await fake.start();
    try {
      final result = await directoryLogin(base, 'zhang', 'StrongPass123');
      expect(result.computers, hasLength(2));
      expect(result.hasMultiple, isTrue);
      // The default is what legacy clients would connect to.
      expect(result.defaultUrl, 'https://omen.corp.com');
      expect(result.computers.first.name, 'OMEN');
      expect(result.computers.first.isDefault, isTrue);
      expect(result.computers.last.id, 'mac');
    } finally {
      await fake.stop();
    }
  });

  test('resolve returns the named computer of this account', () async {
    final seen = <String, dynamic>{};
    final fake = _FakeDirectory((path, body) {
      expect(path, '/directory/resolve');
      seen.addAll(body);
      return {
        'status': 200,
        'body': {
          'ok': true,
          'username': 'zhang',
          'computer': {
            'id': 'mac',
            'name': 'MacBook',
            'subdomain': 'mac.corp.com',
            'default': false,
          },
        },
      };
    });
    final base = await fake.start();
    try {
      final computer = await directoryResolve(
        base,
        username: 'zhang',
        password: 'StrongPass123',
        computerId: 'mac',
      );
      expect(seen['computerId'], 'mac');
      expect(computer.id, 'mac');
      expect(computer.url, 'https://mac.corp.com');
    } finally {
      await fake.stop();
    }
  });
}

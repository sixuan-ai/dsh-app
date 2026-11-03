/// Native access to the shared Sixuan email account service.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const kSixuanAccountsOrigin = 'https://accounts.sixuanai.com';

class SixuanAccountError implements Exception {
  const SixuanAccountError(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SixuanSession {
  const SixuanSession({
    required this.token,
    required this.email,
    required this.name,
    required this.expiresAt,
  });
  final String token;
  final String email;
  final String name;
  final DateTime expiresAt;
  Map<String, dynamic> toJson() => {
    'token': token,
    'email': email,
    'name': name,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };
  factory SixuanSession.fromJson(Map<String, dynamic> value) {
    final token = value['token'];
    if (token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token) ||
        value['email'] is! String ||
        value['name'] is! String ||
        value['expiresAt'] is! int) {
      throw const FormatException('账号会话无效');
    }
    return SixuanSession(
      token: token,
      email: value['email'] as String,
      name: value['name'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(value['expiresAt'] as int),
    );
  }
}

class SixuanAccountStore {
  SixuanAccountStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage storage;
  static const key = 'xharness.sixuan.account.v1';
  Future<void> _pending = Future<void>.value();
  Future<void> _write(String? value) {
    final next = _pending.then(
      (_) => value == null
          ? storage.delete(key: key)
          : storage.write(key: key, value: value),
    );
    _pending = next.catchError((_) {});
    return next;
  }

  Future<void> save(SixuanSession session) =>
      _write(jsonEncode(session.toJson()));
  Future<void> clear() => _write(null);
  Future<SixuanSession?> load() async {
    final raw = await storage.read(key: key);
    if (raw == null) return null;
    try {
      final session = SixuanSession.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      if (session.expiresAt.isAfter(DateTime.now())) return session;
    } on FormatException {
      /* Discard only malformed or expired session data. */
    } on TypeError {
      /* A saved older/corrupt value must not authorize access. */
    }
    await clear();
    return null;
  }
}

class SixuanAccountApi {
  SixuanAccountApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  String newDeviceId() =>
      'xharness-${List.generate(20, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, dynamic>? data,
    String? token,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final uri = Uri.parse('$kSixuanAccountsOrigin/api/$path');
      final response =
          await (data == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(data)))
              .timeout(const Duration(seconds: 40));
      Map<String, dynamic> value;
      try {
        value = (jsonDecode(response.body) as Map).cast<String, dynamic>();
      } catch (_) {
        throw SixuanAccountError(
          '账号服务暂时不可用，请稍后重试',
          status: response.statusCode,
        );
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          value['error'] != null) {
        throw SixuanAccountError(
          value['error'] is String ? value['error'] as String : '请求失败，请稍后重试',
          status: response.statusCode,
        );
      }
      return value;
    } on TimeoutException {
      throw const SixuanAccountError('请求超时，请检查网络后重试');
    } on http.ClientException {
      throw const SixuanAccountError('无法连接账号服务，请检查网络后重试');
    }
  }

  Future<Map<String, dynamic>> passwordLogin({
    required String email,
    required String password,
    required String deviceId,
    bool remember = false,
  }) => _call(
    'app/login',
    data: {
      'email': email,
      'password': password,
      'uuid': deviceId,
      'autoLogin': remember,
    },
  );

  Future<Map<String, dynamic>> requestCode({
    required String mode,
    required String email,
    required String password,
    required String name,
    required String deviceId,
  }) => _call(
    mode == 'register'
        ? 'register'
        : mode == 'recover'
        ? 'password-reset/request'
        : 'login',
    data: mode == 'recover'
        ? {'email': email, 'uuid': deviceId}
        : {
            'email': email,
            'username': email,
            'password': password,
            'display_name': name,
            'type': 'account',
            'uuid': deviceId,
          },
  );
  Future<Map<String, dynamic>> verifyCode({
    required String mode,
    required String secret,
    required String code,
    required String deviceId,
    bool remember = false,
    String? password,
  }) => _call(
    mode == 'register'
        ? 'register/verify'
        : mode == 'recover'
        ? 'password-reset/confirm'
        : 'login',
    data: {
      'type': 'email_code',
      'secret': secret,
      'verificationCode': code,
      'uuid': deviceId,
      'autoLogin': remember,
      if (mode == 'recover') 'password': password ?? '',
    },
  );
  SixuanSession sessionFromResult(
    Map<String, dynamic> value, {
    required bool remember,
  }) {
    final user = (value['user'] as Map?)?.cast<String, dynamic>();
    final session = SixuanSession.fromJson({
      'token': value['access_token'],
      'email': user?['email'],
      'name': user?['display_name'] ?? user?['name'] ?? user?['email'],
      'expiresAt': DateTime.now()
          .add(Duration(hours: remember ? 168 : 12))
          .millisecondsSinceEpoch,
    });
    return session;
  }

  Future<void> validate(SixuanSession session) async {
    await _call('currentUser', token: session.token);
  }

  Future<void> logout(SixuanSession session) async {
    await _call('logout', data: {}, token: session.token);
  }

  void close() => _client.close();
}

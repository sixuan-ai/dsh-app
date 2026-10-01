/// In-app update: fetches a release manifest over HTTP, compares build
/// numbers, downloads the APK with progress, verifies it, and hands it to
/// the Android installer channel.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One release advertised by the update manifest.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.url,
    this.notes,
    this.size,
    this.sha256,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String?,
        size: (json['size'] as num?)?.toInt(),
        sha256: json['sha256'] as String?,
      );

  final String version;

  /// Android versionCode; the update decision compares this, never the name.
  final int versionCode;
  final String url;
  final String? notes;
  final int? size;
  final String? sha256;
}

/// Manifest fetch outcome: exactly one of [info] / [error] is set.
class UpdateCheck {
  UpdateCheck({this.info, this.error});

  final UpdateInfo? info;

  /// User-facing failure reason (HTTP status, network error, bad shape).
  final String? error;
}

/// Manifest fetch + APK download against a releases endpoint.
class UpdateChecker {
  UpdateChecker({
    this.username,
    this.password,
    @visibleForTesting this.clientFactory,
    @visibleForTesting this.connectTimeout = const Duration(seconds: 20),
    @visibleForTesting this.stallTimeout = const Duration(seconds: 15),
  });

  /// Basic credentials reused from the server login; optional so manifest
  /// endpoints without auth_basic keep working.
  final String? username;
  final String? password;

  /// Injectable transport for tests; defaults to a fresh global client per
  /// download attempt.
  final http.Client Function()? clientFactory;

  /// Time until response headers arrive; a dead connection aborts here.
  final Duration connectTimeout;

  /// Max gap between received chunks before the stream is declared stalled.
  final Duration stallTimeout;

  Map<String, String> get _headers {
    final user = username;
    final pass = password;
    if (user == null || user.isEmpty) return const {};
    return {
      'authorization':
          'Basic ${base64Encode(utf8.encode('$user:${pass ?? ''}'))}',
    };
  }

  /// Fetches and parses the manifest; failures report a concrete reason.
  Future<UpdateCheck> check(String manifestUrl) async {
    http.Response response;
    try {
      response = await http
          .get(Uri.parse(manifestUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      final text = error.toString();
      return UpdateCheck(
          error:
              '网络错误 (${text.length > 60 ? '${text.substring(0, 60)}…' : text})');
    }
    if (response.statusCode != 200) {
      return UpdateCheck(error: 'HTTP ${response.statusCode}');
    }
    try {
      final info = UpdateInfo.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
      if (info.versionCode <= 0 || info.url.isEmpty) {
        return UpdateCheck(error: '清单缺少 versionCode/url');
      }
      return UpdateCheck(info: info);
    } catch (_) {
      return UpdateCheck(error: '清单不是合法 JSON');
    }
  }

  /// Downloads the APK into the app cache, reporting received/total bytes,
  /// and verifies the sha256 when the manifest carries one.
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final updates = Directory('${dir.path}/updates');
    await updates.create(recursive: true);
    final target = File('${updates.path}/dsh-app-${info.version}.apk');
    return downloadTo(info, target, onProgress: onProgress);
  }

  /// Streams the APK into [target]. A stalled connection (no headers in
  /// [connectTimeout], no bytes for [stallTimeout]) aborts the attempt and is
  /// retried once automatically; a second stall surfaces the failure so the
  /// UI shows the retry dialog instead of hanging at 0% forever.
  @visibleForTesting
  Future<File> downloadTo(
    UpdateInfo info,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) async {
    try {
      return await _downloadOnce(info, target, onProgress: onProgress);
    } on TimeoutException {
      // A retry from scratch re-announces the fresh progress window.
      onProgress?.call(0, info.size);
      return _downloadOnce(info, target, onProgress: onProgress);
    }
  }

  Future<File> _downloadOnce(
    UpdateInfo info,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = clientFactory?.call() ?? http.Client();
    IOSink? sink;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(info.url))
            ..headers.addAll(_headers))
          .timeout(connectTimeout);
      if (response.statusCode != 200) {
        throw HttpException('下载失败: HTTP ${response.statusCode}');
      }
      sink = target.openWrite();
      final digest = info.sha256 != null ? AccumulatorSink<Digest>() : null;
      final byteSink =
          digest != null ? sha256.startChunkedConversion(digest) : null;
      var received = 0;
      final total = response.contentLength ?? info.size;
      final iterator = StreamIterator<List<int>>(response.stream);
      try {
        while (await iterator.moveNext().timeout(stallTimeout)) {
          final chunk = iterator.current;
          sink.add(chunk);
          byteSink?.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await iterator.cancel();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      byteSink?.close();
      final expected = info.sha256;
      if (expected != null && digest!.events.single.toString() != expected) {
        await target.delete();
        throw const HttpException('下载校验失败: sha256 不匹配');
      }
      return target;
    } catch (_) {
      // Never leave a partial APK behind for a later install to trip over.
      await sink?.close();
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Opens the system installer for a downloaded APK.
  Future<void> install(File apk) {
    return _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  /// Whether the user already granted install-unknown-apps to this app.
  Future<bool> canInstall() async {
    return await _channel.invokeMethod<bool>('canInstallApk') ?? false;
  }

  /// Opens the system settings page granting install-unknown-apps.
  Future<void> requestInstallPermission() {
    return _channel.invokeMethod<void>('requestInstallPermission');
  }

  static const _channel = MethodChannel('dev.dsh.dsh_mobile/installer');
}

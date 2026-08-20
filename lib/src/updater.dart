/// In-app update: fetches a release manifest over HTTP, compares build
/// numbers, downloads the APK with progress, verifies it, and hands it to
/// the Android installer channel.
library;

import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
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

/// Manifest fetch + APK download against a releases endpoint.
class UpdateChecker {
  UpdateChecker({this.username, this.password});

  /// Basic credentials reused from the server login; optional so manifest
  /// endpoints without auth_basic keep working.
  final String? username;
  final String? password;

  Map<String, String> get _headers {
    final user = username;
    final pass = password;
    if (user == null || user.isEmpty) return const {};
    return {
      'authorization':
          'Basic ${base64Encode(utf8.encode('$user:${pass ?? ''}'))}',
    };
  }

  /// Fetches and parses the manifest; null on any network/shape failure.
  Future<UpdateInfo?> fetchManifest(String manifestUrl) async {
    try {
      final response = await http
          .get(Uri.parse(manifestUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final info =
          UpdateInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      if (info.versionCode <= 0 || info.url.isEmpty) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK into the app cache, reporting received/total bytes,
  /// and verifies the sha256 when the manifest carries one.
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final response = await client.send(
          http.Request('GET', Uri.parse(info.url))..headers.addAll(_headers));
      if (response.statusCode != 200) {
        throw HttpException('下载失败: HTTP ${response.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final updates = Directory('${dir.path}/updates');
      await updates.create(recursive: true);
      final file = File('${updates.path}/dsh-app-${info.version}.apk');
      final sink = file.openWrite();
      final digest = info.sha256 != null ? AccumulatorSink<Digest>() : null;
      final byteSink =
          digest != null ? sha256.startChunkedConversion(digest) : null;
      var received = 0;
      final total = response.contentLength ?? info.size;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        byteSink?.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      byteSink?.close();
      final expected = info.sha256;
      if (expected != null && digest!.events.single.toString() != expected) {
        await file.delete();
        throw const HttpException('下载校验失败: sha256 不匹配');
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Opens the system installer for a downloaded APK.
  Future<void> install(File apk) {
    return _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  static const _channel = MethodChannel('dev.dsh.dsh_mobile/installer');
}

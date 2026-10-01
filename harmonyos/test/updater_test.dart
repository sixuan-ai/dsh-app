/// Downloader resilience: stalled connections abort and retry once instead
/// of hanging at 0% forever; partial files never survive a failed attempt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dsh_mobile/src/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A client whose send() never completes (dead connection).
class _HangOnConnectClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// Emits one chunk and then never again (stalled stream mid-download).
class _StallAfterFirstChunkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final controller = StreamController<List<int>>()
      ..add(utf8.encode('partial-data'));
    return Future.value(
      http.StreamedResponse(controller.stream, 200, contentLength: 100),
    );
  }
}

/// Serves the full body in one chunk.
class _GoodClient extends http.BaseClient {
  _GoodClient(this.body);

  final List<int> body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => Future.value(
        http.StreamedResponse(
          Stream.value(body),
          200,
          contentLength: body.length,
        ),
      );
}

UpdateInfo info({String? sha256}) => UpdateInfo(
      version: '9.9.9',
      versionCode: 999,
      url: 'https://example.com/app.apk',
      size: 12,
      sha256: sha256,
    );

void main() {
  late Directory tempDir;
  late File target;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('updater_test_');
    target = File('${tempDir.path}/app.apk');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('stalled connect aborts and surfaces TimeoutException after retry',
      () async {
    final checker = UpdateChecker(
      clientFactory: _HangOnConnectClient.new,
      connectTimeout: const Duration(milliseconds: 120),
      stallTimeout: const Duration(milliseconds: 120),
    );
    await expectLater(
      checker.downloadTo(info(), target),
      throwsA(isA<TimeoutException>()),
    );
    expect(await target.exists(), isFalse, reason: 'no partial file left');
  });

  test('mid-stream stall aborts and cleans the partial file', () async {
    final checker = UpdateChecker(
      clientFactory: _StallAfterFirstChunkClient.new,
      connectTimeout: const Duration(seconds: 2),
      stallTimeout: const Duration(milliseconds: 120),
    );
    await expectLater(
      checker.downloadTo(info(), target),
      throwsA(isA<TimeoutException>()),
    );
    expect(await target.exists(), isFalse);
  });

  test('one stall then success: retry completes the download', () async {
    final body = utf8.encode('apk-bytes');
    var attempt = 0;
    final progress = <int>[];
    final checker = UpdateChecker(
      clientFactory: () =>
          attempt++ == 0 ? _HangOnConnectClient() : _GoodClient(body),
      connectTimeout: const Duration(milliseconds: 120),
      stallTimeout: const Duration(milliseconds: 120),
    );
    final file = await checker.downloadTo(
      info(sha256: sha256.convert(body).toString()),
      target,
      onProgress: (received, total) => progress.add(received),
    );
    expect(attempt, 2, reason: 'one stall + one retry');
    expect(await file.readAsString(), 'apk-bytes');
    expect(progress.last, body.length);
  });

  test('sha256 mismatch deletes the file and reports the error', () async {
    final checker = UpdateChecker(
      clientFactory: () => _GoodClient(utf8.encode('tampered')),
    );
    await expectLater(
      checker.downloadTo(info(sha256: 'deadbeef'), target),
      throwsA(isA<HttpException>()),
    );
    expect(await target.exists(), isFalse);
  });

  test('HTTP error surfaces immediately without retry hang', () async {
    final forbidden = UpdateChecker(
      clientFactory: _ForbiddenClient.new,
    );
    await expectLater(
      forbidden.downloadTo(info(), target),
      throwsA(
        predicate((e) => e is HttpException && e.message.contains('401')),
      ),
    );
    expect(await target.exists(), isFalse);
  });
}

class _ForbiddenClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.value(http.StreamedResponse(const Stream.empty(), 401));
}

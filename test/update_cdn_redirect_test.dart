import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dsh_mobile/src/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

void main() {
  test(
    'existing authenticated updater follows public CDN redirect without forwarding account credentials',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final temp = await Directory.systemTemp.createTemp('xharness-cdn-');
      final bytes = utf8.encode('test signed APK payload');
      String? originAuthorization;
      String? cdnAuthorization;
      var cdnRequests = 0;
      final originSubscription = origin.listen((request) async {
        originAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${cdn.port}/xharness/dsh-app-2.5.1.apk',
        );
        await request.response.close();
      });
      final cdnSubscription = cdn.listen((request) async {
        cdnRequests++;
        cdnAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      try {
        final checker = UpdateChecker(
          username: 'test-account',
          password: 'test-password',
          clientFactory: () =>
              IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
        );
        final info = UpdateInfo(
          version: '2.5.1',
          versionCode: 2143,
          url:
              'http://localhost:${origin.port}/releases-public/dsh-app-2.5.1.apk',
          size: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        );
        final file = await checker.downloadTo(
          info,
          File('${temp.path}/release.apk'),
        );
        expect(await file.readAsBytes(), bytes);
        expect(originAuthorization, startsWith('Basic '));
        expect(cdnRequests, 1);
        expect(cdnAuthorization, isNull);
      } finally {
        await originSubscription.cancel();
        await cdnSubscription.cancel();
        await origin.close(force: true);
        await cdn.close(force: true);
        await temp.delete(recursive: true);
      }
    },
  );
}

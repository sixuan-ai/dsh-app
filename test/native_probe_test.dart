import 'package:dsh_mobile/src/native_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats successful native probe against failed Dart TLS', () {
    expect(
      formatNativeProbeResult({'ok': true, 'elapsedMs': 87}),
      '原生 OkHttp 探测成功（87ms），Dart TLS 失败',
    );
  });

  test('formats native probe failure details', () {
    expect(
      formatNativeProbeResult({
        'ok': false,
        'elapsedMs': 31,
        'errorType': 'java.net.SocketException',
        'error': 'Connection reset',
      }),
      '原生 OkHttp 也失败（31ms）：java.net.SocketException: Connection reset',
    );
  });
}

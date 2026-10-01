import 'package:dsh_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connectionModeForUrl', () {
    test('derives the mode from the live server URL', () {
      expect(connectionModeForUrl(kDirectServerUrl), 'direct');
      expect(connectionModeForUrl(kDirectServerFallbackUrl), 'direct');
      expect(connectionModeForUrl(kDefaultServerUrl), 'public');
      expect(connectionModeForUrl(''), 'public');
    });

    test('matches the LAN route only against the persisted local URL', () {
      const lanUrl = 'http://192.168.1.5:3080';
      expect(connectionModeForUrl(lanUrl, localUrl: lanUrl), 'lan');
      expect(
        connectionModeForUrl('http://192.168.1.6:3080', localUrl: lanUrl),
        'public',
      );
      // A LAN URL is never 'direct' even when no local URL is known yet.
      expect(
        connectionModeForUrl(kDirectServerUrl, localUrl: lanUrl),
        'direct',
      );
    });

    test('empty or unknown URLs fall back to public', () {
      expect(
        connectionModeForUrl('https://example.com', localUrl: null),
        'public',
      );
    });
  });
}

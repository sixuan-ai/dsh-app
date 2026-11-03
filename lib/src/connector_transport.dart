/// Dedicated, authority-scoped TLS trust for a physically paired computer.
library;

import 'dart:io';
import 'package:crypto/crypto.dart';

HttpClient connectorHttpClient(Uri origin, String? fingerprint) {
  if (fingerprint == null) return HttpClient();
  if (origin.scheme != 'https' ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
    throw const FormatException('配对连接必须使用 HTTPS 和有效证书指纹');
  }
  // An empty root store makes *every* server cert pass through this pin check,
  // including an otherwise CA-valid certificate with the wrong fingerprint.
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.badCertificateCallback = (cert, host, port) =>
      host == origin.host &&
      port == origin.port &&
      sha256.convert(cert.der).toString() == fingerprint;
  return client;
}

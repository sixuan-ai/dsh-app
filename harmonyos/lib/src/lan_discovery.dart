/// LAN discovery for the local DSH host. Two strategies run in order:
/// 1. mDNS (`_dsh._tcp`, published by avahi) — the standard mechanism, but
///    multicast can be filtered by some routers or Android ROMs.
/// 2. A TCP port scan of the phone's own /24 subnet — no multicast needed,
///    works whenever the auth proxy listens on the LAN.
library;

import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// The mDNS service type published by the host (avahi service file).
const kDshMdnsType = '_dsh._tcp';

/// Auth-proxy port probed during the subnet fallback scan.
const kDshLanPort = 3081;

/// One discovered host.
class LanDshDevice {
  const LanDshDevice({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;

  /// Resolved IP address (string) or hostname fallback.
  final String host;
  final int port;

  String get url => 'http://$host:$port';
}

/// Discovers DSH hosts on the LAN: mDNS first, subnet scan as fallback.
Future<List<LanDshDevice>> discoverLocalDsh({
  Duration mdnsTimeout = const Duration(seconds: 4),
}) async {
  final mdns = await discoverDshDevices(
    timeout: mdnsTimeout,
  ).catchError((_) => const <LanDshDevice>[]);
  if (mdns.isNotEmpty) return mdns;
  return scanLanDsh();
}

/// mDNS lookup for `_dsh._tcp`, resolving PTR → SRV → A.
Future<List<LanDshDevice>> discoverDshDevices({
  MDnsClient? client,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final mdns = client ?? MDnsClient();
  final owned = client == null;
  if (owned) await mdns.start();
  try {
    final found = <LanDshDevice>[];
    // lookup() closes its stream at the timeout; no extra .timeout() wrapper
    // here — it would throw on a quiet network instead of returning empty.
    await for (final ptr in mdns.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(kDshMdnsType),
      timeout: timeout,
    )) {
      final domain = ptr.domainName;
      await for (final srv in mdns.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(domain),
        timeout: timeout,
      )) {
        var resolved = false;
        try {
          await for (final address in mdns.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: timeout,
          )) {
            found.add(
              LanDshDevice(
                name: _serviceName(domain),
                host: address.address.address,
                port: srv.port,
              ),
            );
            resolved = true;
          }
        } catch (_) {
          // A lookup failed; fall back to the SRV target hostname below.
        }
        if (!resolved) {
          found.add(
            LanDshDevice(
              name: _serviceName(domain),
              host: srv.target.replaceFirst(RegExp(r'\.$'), ''),
              port: srv.port,
            ),
          );
        }
      }
    }
    return found;
  } finally {
    if (owned) mdns.stop();
  }
}

/// Scans the phone's own /24 subnet(s) for an open DSH port. No multicast
/// involved, so this survives AP-side multicast filtering.
Future<List<LanDshDevice>> scanLanDsh({
  int port = kDshLanPort,
  Duration connectTimeout = const Duration(milliseconds: 250),
  int batchSize = 32,
}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  final prefixes = <String>{};
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final parts = address.address.split('.');
      if (parts.length == 4 && !address.address.startsWith('127.')) {
        prefixes.add(parts.sublist(0, 3).join('.'));
      }
    }
  }
  final found = <LanDshDevice>[];
  for (final prefix in prefixes) {
    for (var start = 1; start < 255; start += batchSize) {
      final batch = <Future<LanDshDevice?>>[];
      for (var i = start; i < 255 && i < start + batchSize; i++) {
        final host = '$prefix.$i';
        batch.add(
          Future(() async {
            try {
              final socket = await Socket.connect(
                host,
                port,
                timeout: connectTimeout,
              );
              socket.destroy();
              return LanDshDevice(name: host, host: host, port: port);
            } catch (_) {
              return null;
            }
          }),
        );
      }
      found.addAll((await Future.wait(batch)).whereType<LanDshDevice>());
    }
  }
  return found;
}

String _serviceName(String domain) =>
    domain.replaceFirst(RegExp(r'\._dsh\._tcp\.?$'), '');

/// LAN discovery for the local DSH host via mDNS (`_dsh._tcp`). The host
/// publishes the service with avahi; the app resolves candidate addresses so
/// the user can pick one instead of typing an IP by hand.
library;

import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

/// The mDNS service type published by the host (avahi service file).
const kDshMdnsType = '_dsh._tcp';

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

String _serviceName(String domain) =>
    domain.replaceFirst(RegExp(r'\._dsh\._tcp\.?$'), '');

/// Queries `_dsh._tcp` on the local network and resolves each answer to an
/// address:port pair. [client] is injectable for tests.
Future<List<LanDshDevice>> discoverDshDevices({
  MDnsClient? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final mdns = client ?? MDnsClient();
  final owned = client == null;
  if (owned) await mdns.start();
  try {
    final found = <LanDshDevice>[];
    await for (final ptr
        in mdns
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(kDshMdnsType),
              timeout: timeout,
            )
            .timeout(timeout)) {
      final domain = ptr.domainName;
      await for (final srv
          in mdns
              .lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(domain),
                timeout: timeout,
              )
              .timeout(timeout)) {
        var resolved = false;
        try {
          await for (final address
              in mdns
                  .lookup<IPAddressResourceRecord>(
                    ResourceRecordQuery.addressIPv4(srv.target),
                    timeout: timeout,
                  )
                  .timeout(timeout)) {
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
          // A lookup failed; fall back to the SRV target hostname.
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

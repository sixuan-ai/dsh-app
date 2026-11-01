/// Connection-mode status and switching sheet.
library;

import 'package:flutter/material.dart';

import 'src/l10n.dart';
import 'src/protocol.dart';
import 'src/theme.dart';
import 'connection_center_banner.dart';

class ConnectionCenterSheet extends StatelessWidget {
  const ConnectionCenterSheet({
    super.key,
    required this.connectionMode,
    required this.checkingLocal,
    required this.localAvailable,
    required this.onSwitchRemote,
    required this.onSwitchLocal,
    required this.onRefreshLocal,
    this.onSwitchDirect,
    this.localUrl,
    this.onSetLocalAddress,
    this.onAutoSearchLocal,
    this.computers = const [],
    this.currentComputerId,
    this.onSwitchComputer,
  });

  final String connectionMode;
  final bool checkingLocal;
  final bool localAvailable;
  final VoidCallback onSwitchRemote;
  final VoidCallback onSwitchLocal;
  final VoidCallback onRefreshLocal;

  /// Switches to the direct Shenzhen relay (low-latency route).
  final VoidCallback? onSwitchDirect;

  /// Persisted LAN address of the local computer (empty when unset).
  final String? localUrl;

  /// Opens the local-address editor (HomePage owns the dialog).
  final VoidCallback? onSetLocalAddress;

  /// Runs mDNS discovery for DSH hosts on the LAN.
  final VoidCallback? onAutoSearchLocal;

  /// The account's computers, as last reported by the directory at login.
  final List<AccountComputer> computers;

  /// Id of the computer the socket is currently connected to.
  final String? currentComputerId;

  /// Switches to one of the account's computers.
  final void Function(AccountComputer computer)? onSwitchComputer;

  String get _currentLabel {
    if (connectionMode == 'public') {
      for (final computer in computers) {
        if (computer.id == currentComputerId) return computer.name;
      }
    }
    return switch (connectionMode) {
      'lan' => S.localComputer,
      'direct' => S.szServer,
      _ => S.hkServer,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.connectionCenter,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(S.switchTip, style: TextStyle(color: P.textSecondary)),
              const SizedBox(height: 14),
              CurrentConnectionBanner(label: _currentLabel),
              const SizedBox(height: 14),
              // The account's computers: one entry per provisioned machine, so
              // the user can jump between their own computers. Each belongs to a
              // different instance, so switching replaces the visible sessions.
              if (computers.isNotEmpty) ...[
                Text(
                  S.myComputers,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: P.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final computer in computers) ...[
                  _ConnectionCard(
                    icon: Icons.computer_outlined,
                    title: computer.name.isEmpty ? computer.id : computer.name,
                    subtitle: computer.id == currentComputerId
                        ? S.currentlyUsing
                        : computer.subdomain,
                    active: computer.id == currentComputerId,
                    actionLabel: S.switchToThis,
                    onSwitch: () {
                      Navigator.pop(context);
                      onSwitchComputer?.call(computer);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 6),
              ],
              if (computers.isEmpty)
                _ConnectionCard(
                  icon: Icons.cloud_outlined,
                  title: S.hkServer,
                  subtitle: connectionMode == 'public'
                      ? S.currentlyUsing
                      : S.hkServerDesc,
                  active: connectionMode == 'public',
                  actionLabel: S.switchBackToHk,
                  onSwitch: () {
                    Navigator.pop(context);
                    onSwitchRemote();
                  },
                ),
              if (computers.isEmpty && onSwitchDirect != null) ...[
                const SizedBox(height: 10),
                _ConnectionCard(
                  icon: Icons.bolt_rounded,
                  title: S.szServer,
                  subtitle: connectionMode == 'direct'
                      ? S.currentlyUsing
                      : S.szServerDesc,
                  active: connectionMode == 'direct',
                  actionLabel: S.switchToSz,
                  onSwitch: () {
                    Navigator.pop(context);
                    onSwitchDirect!();
                  },
                ),
              ],
              const SizedBox(height: 10),
              _ConnectionCard(
                icon: Icons.lan_outlined,
                title: S.localComputer,
                subtitle: connectionMode == 'lan'
                    ? S.currentlyUsing
                    : checkingLocal
                    ? S.checkingLocal
                    : localAvailable
                    ? S.localDescAvailable
                    : (localUrl == null || localUrl!.isEmpty)
                    ? S.localAddressEmpty
                    : localUrl!,
                active: connectionMode == 'lan',
                available: localAvailable,
                checking: checkingLocal,
                actionLabel: S.switchToLocal,
                onSwitch: () {
                  Navigator.pop(context);
                  onSwitchLocal();
                },
              ),
              if (onSetLocalAddress != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onSetLocalAddress!();
                    },
                    icon: const Icon(
                      Icons.edit_location_alt_outlined,
                      size: 18,
                    ),
                    label: Text(S.setLocalAddress),
                  ),
                ),
              ],
              if (onAutoSearchLocal != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onAutoSearchLocal!();
                    },
                    icon: const Icon(Icons.wifi_find_outlined, size: 18),
                    label: Text(S.autoSearchLocal),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onRefreshLocal();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(S.retestLocal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.actionLabel,
    required this.onSwitch,
    this.available = true,
    this.checking = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final String actionLabel;
  final VoidCallback onSwitch;
  final bool available;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active ? P.accent.withValues(alpha: 0.10) : P.fillSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? P.accent.withValues(alpha: 0.35) : P.fillLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active ? P.accent.withValues(alpha: 0.16) : P.fillMedium,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 19,
              color: active ? P.accentLight : P.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: active ? P.accentLight : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: active ? P.accentLight : P.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: P.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: P.success, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    '正在使用',
                    style: TextStyle(
                      color: P.success,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else if (checking)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.tonal(
              onPressed: available ? onSwitch : null,
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

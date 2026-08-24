/// Connection-mode status and switching sheet.
library;

import 'package:flutter/material.dart';

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
  });

  final String connectionMode;
  final bool checkingLocal;
  final bool localAvailable;
  final VoidCallback onSwitchRemote;
  final VoidCallback onSwitchLocal;
  final VoidCallback onRefreshLocal;

  /// Switches to the direct Shenzhen relay (low-latency route).
  final VoidCallback? onSwitchDirect;

  String get _currentLabel => switch (connectionMode) {
    'lan' => '本地连接',
    'direct' => '深圳直连',
    _ => '远程连接',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '连接中心',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '切换连接不会退出账号。正在生成内容时建议等待完成后再切换。',
              style: TextStyle(color: P.textSecondary),
            ),
            const SizedBox(height: 14),
            CurrentConnectionBanner(label: _currentLabel),
            const SizedBox(height: 14),
            _ConnectionCard(
              icon: Icons.cloud_outlined,
              title: '远程连接',
              subtitle: connectionMode == 'public' ? '当前正在使用' : '通过官网连接，适合外出使用',
              active: connectionMode == 'public',
              actionLabel: '切换到远程',
              onSwitch: () {
                Navigator.pop(context);
                onSwitchRemote();
              },
            ),
            if (onSwitchDirect != null) ...[
              const SizedBox(height: 10),
              _ConnectionCard(
                icon: Icons.bolt_rounded,
                title: '深圳直连',
                subtitle: connectionMode == 'direct'
                    ? '当前正在使用'
                    : '不经过 Cloudflare，国内延迟更低更稳',
                active: connectionMode == 'direct',
                actionLabel: '切换到深圳',
                onSwitch: () {
                  Navigator.pop(context);
                  onSwitchDirect!();
                },
              ),
            ],
            const SizedBox(height: 10),
            _ConnectionCard(
              icon: Icons.lan_outlined,
              title: '本地连接',
              subtitle: connectionMode == 'lan'
                  ? '当前正在使用'
                  : checkingLocal
                  ? '正在检查电脑…'
                  : localAvailable
                  ? '本地电脑可用，通常速度更快'
                  : '当前未检测到本地电脑',
              active: connectionMode == 'lan',
              available: localAvailable,
              checking: checkingLocal,
              actionLabel: '切换到本地',
              onSwitch: () {
                Navigator.pop(context);
                onSwitchLocal();
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onRefreshLocal();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重新检测本地连接'),
              ),
            ),
          ],
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

/// Connection-mode status and switching sheet.
library;

import 'package:flutter/material.dart';

import 'src/theme.dart';

class ConnectionCenterSheet extends StatelessWidget {
  const ConnectionCenterSheet({
    super.key,
    required this.connectionMode,
    required this.checkingLocal,
    required this.localAvailable,
    required this.onSwitchRemote,
    required this.onSwitchLocal,
    required this.onRefreshLocal,
  });

  final String connectionMode;
  final bool checkingLocal;
  final bool localAvailable;
  final VoidCallback onSwitchRemote;
  final VoidCallback onSwitchLocal;
  final VoidCallback onRefreshLocal;

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
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('远程连接'),
              subtitle: Text(
                connectionMode == 'public' ? '当前正在使用' : '通过官网连接，适合外出使用',
              ),
              trailing: connectionMode == 'public'
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : FilledButton.tonal(
                      onPressed: () {
                        Navigator.pop(context);
                        onSwitchRemote();
                      },
                      child: const Text('切换'),
                    ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lan_outlined),
              title: const Text('本地连接'),
              subtitle: Text(
                connectionMode == 'lan'
                    ? '当前正在使用'
                    : checkingLocal
                    ? '正在检查电脑…'
                    : localAvailable
                    ? '本地电脑可用，通常速度更快'
                    : '当前未检测到本地电脑',
              ),
              trailing: connectionMode == 'lan'
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : FilledButton.tonal(
                      onPressed: localAvailable
                          ? () {
                              Navigator.pop(context);
                              onSwitchLocal();
                            }
                          : null,
                      child: const Text('切换'),
                    ),
            ),
            const SizedBox(height: 8),
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

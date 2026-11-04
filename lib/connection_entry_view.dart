/// First screen inside the app before selecting a desktop.
library;

import 'package:flutter/material.dart';
import 'state.dart';
import 'access_policy.dart';
import 'src/theme.dart';
import 'src/ui/neumorphic.dart';

class ConnectionEntryView extends StatelessWidget {
  const ConnectionEntryView({
    super.key,
    required this.state,
    required this.onPair,
    required this.onSettings,
    required this.onAccount,
  });
  final AppState state;
  final VoidCallback onPair, onSettings, onAccount;
  @override
  Widget build(BuildContext context) {
    final muted = P.textSecondary;
    final hasDevices =
        state.savedPairedComputers.isNotEmpty || state.computers.isNotEmpty;
    Widget route(
      IconData icon,
      String title,
      String detail,
      VoidCallback action,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: NeuSurface(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          leading: Icon(
            icon,
            color: icon == Icons.public_rounded ? P.info : P.accent,
            size: 30,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(detail, style: TextStyle(color: muted, height: 1.6)),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: action,
        ),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(
                  state.signedInAccount != null
                      ? Icons.verified_user_outlined
                      : Icons.wifi_rounded,
                  size: 16,
                ),
                label: Text(
                  state.signedInAccount?.email ?? '连接你的电脑 · 无需登录',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '先连接电脑，\n再继续你的任务。',
              style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '电脑运行 xHarness 连接器，手机配对后即可查看工作区、任务进度和对话。',
              style: TextStyle(color: muted, height: 1.8),
            ),
            const SizedBox(height: 24),
            route(
              Icons.wifi_rounded,
              '局域网直连',
              '无需登录，可配对多台电脑，完整使用工作区、任务和模型选择。',
              hasDevices ? onSettings : onPair,
            ),
            route(
              Icons.public_rounded,
              '公网连接',
              '使用已配对电脑的公网入口；电脑需先开启公网访问。',
              hasDevices ? onSettings : onPair,
            ),
            const SizedBox(height: 22),
            NeonButton(
              onPressed: onPair,
              icon: Icons.qr_code_scanner_rounded,
              label: '配对我的电脑',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('连接设置 / 选择电脑'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            TextButton(
              onPressed: onAccount,
              child: Text(
                state.signedInAccount != null ? '我的思玄账号' : '登录 / 注册思玄账号 · 可选',
              ),
            ),
            TextButton.icon(
              onPressed: () => showAccessPolicy(context),
              icon: const Icon(Icons.info_outline_rounded, size: 17),
              label: const Text('功能与权限'),
            ),
          ],
        ),
      ),
    );
  }
}

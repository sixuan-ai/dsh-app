/// Account capabilities are separate from each desktop's authorization.
library;

import 'package:flutter/material.dart';

const kLocalAccessSummary = '无需登录，完整使用局域网功能';
const kLocalAccessLimits = 'App 不按登录状态限制电脑数量、任务次数或模型选择。';
const kComputerPermissionSummary = '操作权限由电脑端授权，登录不会自动获得完全权限。';

Future<void> showAccessPolicy(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AccessPolicySheet(),
    );

class AccessPolicySheet extends StatelessWidget {
  const AccessPolicySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(IconData icon, String title, String detail) => Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(detail, style: const TextStyle(height: 1.7)),
              ],
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '功能与权限',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(kLocalAccessSummary, style: TextStyle(height: 1.7)),
              section(
                Icons.wifi_rounded,
                '无需登录 · 局域网',
                '扫码配对、多电脑切换、工作区与文件、任务与对话、Agent 调用均可使用。\n$kLocalAccessLimits 实际模型与工具由电脑提供。',
              ),
              section(
                Icons.public_rounded,
                '登录后 · 公网',
                '登录后可访问已配对电脑的公网入口。电脑端需要先配置公网连接。',
              ),
              section(
                Icons.verified_user_outlined,
                '权限由电脑授权',
                '$kComputerPermissionSummary 命令执行、文件修改等操作遵循电脑端的授权和确认规则。',
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('我知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

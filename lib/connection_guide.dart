/// Public and LAN connection setup guide.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/theme.dart';
import 'access_policy.dart';

class ConnectionGuideSheet extends StatefulWidget {
  const ConnectionGuideSheet({super.key, this.initialMode = 'public'});

  final String initialMode;

  @override
  State<ConnectionGuideSheet> createState() => _ConnectionGuideSheetState();
}

class _ConnectionGuideSheetState extends State<ConnectionGuideSheet> {
  late String _mode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mode == 'public' ? '远程连接：让官网帮你找到电脑' : '本地连接：手机直连电脑',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '先看适合谁、需要准备什么，再按步骤完成。高级命令可直接点按复制。',
                style: TextStyle(color: P.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => showAccessPolicy(context),
                icon: const Icon(Icons.info_outline_rounded, size: 17),
                label: const Text('功能与权限'),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'public',
                    icon: Icon(Icons.public),
                    label: Text('远程连接'),
                  ),
                  ButtonSegment(
                    value: 'lan',
                    icon: Icon(Icons.wifi),
                    label: Text('本地连接'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
              const SizedBox(height: 18),
              const _GuideStep(
                number: 1,
                title: '安装电脑连接器（Linux）',
                detail:
                    '先安装并启动 DSH，在开源仓库目录运行安装脚本。完成后从电脑应用菜单打开「xHarness 电脑连接器」。已有 DSH 可直接接入。',
                code: 'bash server/connector/install.sh',
              ),
              const _GuideStep(
                number: 2,
                title: '配对我的电脑',
                detail:
                    '手机与电脑连接同一网络，在电脑生成二维码，手机点「连接我的电脑」拍摄或导入二维码，核对名称后确认。二维码 2 分钟内有效，仅能使用一次。',
              ),
              if (_mode == 'public') ...[
                const _GuideStep(
                  number: 3,
                  title: '启用公网入口',
                  detail:
                      '在 App 登录账号。电脑端完成 Tailscale 登录，请网关管理员授权访问连接器。在连接器的公网表单填写网关地址和账号，注册后重新配对手机。离开家后可使用该电脑的公网入口。',
                ),
                const _GuideTip(
                  text:
                      '公网网关仍需管理员首次部署与授权；手机不需要安装 Tailscale。当前安装器仅验证 Linux，Windows/macOS 尚未提供安装包。',
                ),
              ] else ...[
                const _GuideStep(
                  number: 3,
                  title: '连接后查看同步工作区',
                  detail:
                      '电脑保持开机，App 直接访问同一台 DSH 的工作区、任务和对话。访客网络或 AP 隔离可能阻止局域网互访。电脑 IP 改变后请重新配对。',
                ),
                const _GuideTip(
                  text:
                      '$kLocalAccessLimits 局域网连接使用 HTTPS 和二维码证书校验。丢失手机时，在电脑连接器中撤销该设备。',
                ),
              ],
              const SizedBox(height: 8),
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

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.detail,
    this.code,
  });

  final int number;
  final String title;
  final String detail;
  final String? code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: P.brandGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: P.accent.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: P.onAccent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(color: P.textSecondary, height: 1.4),
                ),
                if (code != null) ...[
                  const SizedBox(height: 7),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code!));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('命令已复制')));
                    },
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: P.code,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: P.fillLight),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              code!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Icon(Icons.copy, size: 16, color: P.accentLight),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideTip extends StatelessWidget {
  const _GuideTip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: P.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: P.accent.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(Icons.tips_and_updates_outlined, color: P.accentLight),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: P.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

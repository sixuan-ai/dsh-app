/// Public and LAN connection setup guide.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/theme.dart';

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
              if (_mode == 'public') ...[
                const _GuideStep(
                  number: 1,
                  title: '准备一台保持在线的电脑',
                  detail: '这台电脑就是你的 AI 工作电脑，需要安装并运行 DSH。',
                  code: 'dsh web --no-open',
                ),
                const _GuideStep(
                  number: 2,
                  title: '申请远程连接服务',
                  detail:
                      '目前需要管理员为你的电脑配置安全域名、HTTPS、登录保护和网络隧道。普通用户不需要自己开放路由器端口。',
                ),
                const _GuideStep(
                  number: 3,
                  title: '使用官网账号登录',
                  detail: '管理员绑定完成后，你只需要输入账号和密码，App 会自动找到你的电脑。',
                ),
                const _GuideTip(
                  text: '安全说明：远程连接必须使用 HTTPS 和身份认证。配对码与设备密钥方案仍在规划中，当前不会声称已经支持。',
                ),
              ] else ...[
                const _GuideStep(
                  number: 1,
                  title: '让手机和电脑连接同一可信网络',
                  detail: '访客网络或开启 AP 隔离的 Wi-Fi 可能无法互相访问。',
                ),
                const _GuideStep(
                  number: 2,
                  title: '让电脑只在家里可见',
                  detail: '在可信家庭网络中启动局域网服务，并保持窗口开启。不要把这个端口转发到公网。',
                  code: 'dsh web --host 0.0.0.0 --port 3080 --no-open',
                ),
                const _GuideStep(
                  number: 3,
                  title: '查找电脑局域网 IP',
                  detail:
                      'Linux/macOS 可运行 hostname -I 或在网络设置查看，例如 192.168.1.100。',
                  code: 'hostname -I',
                ),
                const _GuideStep(
                  number: 4,
                  title: '在 App 填写电脑地址',
                  detail: '填写 http://电脑IP:3080。当前直连模式的账号保护取决于电脑前是否配置认证代理。',
                ),
                const _GuideTip(
                  text:
                      '安全说明：只在可信家庭网络使用。离开 Wi-Fi 后不可用；不要在公共网络使用，也不要把 3080 端口开放到互联网。',
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

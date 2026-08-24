/// First-run guide and no-session welcome view.
library;

import 'package:flutter/material.dart';

import 'brand_mark.dart';
import 'src/theme.dart';

class QuickStartSheet extends StatelessWidget {
  const QuickStartSheet({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.add_comment_outlined, '新建会话', '点击右上角或侧边栏“新建会话”，选择电脑上的工作目录。'),
      (Icons.chat_bubble_outline, '发送任务', '像聊天一样描述需求；可以发送文字和图片，也可以用 / 打开快捷命令。'),
      (Icons.approval_outlined, '处理确认', '涉及文件和命令时，App 会弹出审批或问题，请确认后任务才会继续。'),
      (Icons.menu, '管理与更多功能', '左上角菜单可切换会话、查看宠物、连接教程、权限模式和更新。'),
    ];
    return Material(
      color: P.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第一次使用？先看这四步',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '四步快速上手，之后可在“更多功能 → 连接教程”重新查看配置。',
                style: TextStyle(color: P.textSecondary),
              ),
              const SizedBox(height: 18),
              for (final (icon, title, detail) in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: P.accent.withValues(alpha: 0.12),
                    child: Icon(icon, color: P.accentLight),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(detail),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('开始使用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded welcome shown when no session is selected, with quick-start
/// suggestion chips that open a session and send the prompt in one tap.
class EmptySessionView extends StatelessWidget {
  const EmptySessionView({
    super.key,
    required this.onNewSession,
    required this.onSuggestion,
  });

  final VoidCallback onNewSession;

  /// Sends a suggestion as a fresh session's first prompt.
  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    (Icons.code, '帮我 review 一段代码'),
    (Icons.edit_note, '帮我写一份工作周报'),
    (Icons.lightbulb_outline, '给我三个副业点子'),
    (Icons.travel_explore, '规划一个周末短途旅行'),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 76),
            const SizedBox(height: 22),
            Text(
              '开始一个新的对话',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '在下方输入消息,或从左上角菜单选择历史会话',
              textAlign: TextAlign.center,
              style: TextStyle(color: P.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final (icon, label) in _suggestions)
                  Material(
                    color: P.card,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSuggestion(label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: P.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 15, color: P.accentLight),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: P.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            FilledButton.tonalIcon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add),
              label: const Text('新建会话'),
            ),
          ],
        ),
      ),
    );
  }
}

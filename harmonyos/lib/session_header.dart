/// Session title bar and session-level actions.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/l10n.dart';
import 'src/theme.dart';
import 'session_mode_badge.dart';
import 'state.dart';
import 'task_queue.dart';

class SessionHeader extends StatelessWidget implements PreferredSizeWidget {
  const SessionHeader({
    super.key,
    required this.state,
    required this.title,
    required this.subtitleParts,
    required this.onModelPicker,
    required this.onNewSession,
    required this.onRename,
    required this.onRefresh,
    required this.onCheckUpdate,
    required this.onLogout,
  });

  final AppState state;
  final String title;
  final List<String> subtitleParts;
  final VoidCallback onModelPicker;
  final VoidCallback onNewSession;
  final VoidCallback onRename;
  final VoidCallback onRefresh;
  final VoidCallback onCheckUpdate;
  final VoidCallback onLogout;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  /// Shows the full session title (truncated in the bar) for reading.
  void _showFullTitle(BuildContext context) {
    String? cwd;
    for (final row in state.sessions) {
      if (row.sessionId == state.selectedSessionId) {
        cwd = row.cwd;
        break;
      }
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.sessionName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              title,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            if (cwd != null && cwd.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                cwd,
                style: TextStyle(
                  fontSize: 12.5,
                  color: P.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = state.selectedSessionId;
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Tooltip(
                  message: title,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showFullTitle(context),
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              if (sessionId != null) ...[
                const SizedBox(width: 8),
                SessionModeBadge(mode: state.sessionModeOf(sessionId)),
              ],
            ],
          ),
          if (subtitleParts.isNotEmpty)
            Text(
              subtitleParts.join(' · '),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: P.textTertiary),
            ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Divider(height: 0.5, color: P.divider),
      ),
      actions: [
        if (sessionId != null && state.subagents.isNotEmpty)
          SubagentStatusButton(state: state),
        if (sessionId != null && state.hasQueuedTasks)
          TaskQueueButton(state: state),
        if (sessionId != null)
          IconButton(
            tooltip: '切换模型',
            onPressed: state.loadingModels ? null : onModelPicker,
            icon: const Icon(Icons.smart_toy_outlined, size: 21),
          ),
        IconButton(
          tooltip: '新建会话',
          icon: const Icon(Icons.add_comment_outlined),
          onPressed: onNewSession,
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
              case 'refresh':
                onRefresh();
              case 'update':
                onCheckUpdate();
              case 'logout':
                onLogout();
            }
          },
          itemBuilder: (context) => [
            if (sessionId != null)
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('重命名会话'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('刷新列表'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (defaultTargetPlatform == TargetPlatform.android)
              const PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: Icon(Icons.system_update_alt_outlined),
                  title: Text('检查更新'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout),
                title: Text('退出登录'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class SubagentStatusButton extends StatelessWidget {
  const SubagentStatusButton({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final running = state.subagents.where((entry) => entry.running).length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: running > 0 ? '$running 个子代理正在工作' : '查看子代理',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => _SubagentSheet(state: state),
          ),
          icon: Icon(
            Icons.account_tree_outlined,
            color: running > 0 ? P.success : P.textSecondary,
          ),
        ),
        if (running > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 17,
              height: 17,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: P.success,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$running',
                style: TextStyle(
                  color: P.onAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubagentSheet extends StatelessWidget {
  const _SubagentSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '子代理运行状态',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: state.loadingSubagents
                    ? null
                    : state.refreshSubagents,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final agent in state.subagents)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                agent.running
                    ? Icons.autorenew_rounded
                    : Icons.check_circle_outline,
                color: agent.running ? P.success : P.textTertiary,
              ),
              title: Text(
                agent.label?.isNotEmpty == true ? agent.label! : '子代理',
              ),
              subtitle: Text(
                '${agent.mode == 'continuable' ? '可继续' : '单次任务'}${agent.hasChildren ? ' · 包含下级代理' : ''}',
              ),
              trailing: Text(
                agent.running ? '工作中' : '已完成',
                style: TextStyle(
                  color: agent.running ? P.success : P.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

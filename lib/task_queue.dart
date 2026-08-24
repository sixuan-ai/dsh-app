/// Task queue presentation and interactions.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'src/theme.dart';
import 'state.dart';

/// Opens the server-authoritative pending task list from the top bar.
class TaskQueueButton extends StatelessWidget {
  const TaskQueueButton({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Badge(
      label: Text('${state.pendingTaskCount}'),
      child: IconButton(
        tooltip: '任务队列',
        icon: const Icon(Icons.playlist_play_rounded),
        color: P.accentLight,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _TaskQueueSheet(state: state),
        ),
      ),
    );
  }
}

/// Server-authoritative pending task list for the selected session.
class _TaskQueueSheet extends StatefulWidget {
  const _TaskQueueSheet({required this.state});

  final AppState state;

  @override
  State<_TaskQueueSheet> createState() => _TaskQueueSheetState();
}

class _TaskQueueSheetState extends State<_TaskQueueSheet> {
  String? _busyId;

  Future<void> _edit(QueuedTask task) async {
    final controller = TextEditingController(text: task.text);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑排队任务'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '输入任务内容'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() => _busyId = task.id);
    final accepted = await widget.state.updateQueuedTask(task.id, text);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!accepted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('编辑任务失败，请稍后重试')));
    }
  }

  Future<void> _remove(QueuedTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除排队任务?'),
        content: const Text('删除后，这个任务不会再交给 AI 处理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busyId = task.id);
    final accepted = await widget.state.removeQueuedTask(task.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!accepted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除任务失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final tasks = widget.state.queuedTasks;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '任务队列',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '待处理 ${widget.state.pendingTaskCount} 个',
                      style: TextStyle(color: P.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'AI 完成当前任务后，会按顺序自动继续处理。',
                  style: TextStyle(color: P.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.playlist_remove_rounded,
                            size: 34,
                            color: P.textTertiary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '当前没有排队任务',
                            style: TextStyle(color: P.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.55,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final task = tasks[index];
                        final label = task.placement == 'steering'
                            ? '即将插入'
                            : '排队 ${index + 1}';
                        final content = task.text.trim().isEmpty
                            ? (task.imageCount > 0
                                  ? '[${task.imageCount} 张图片]'
                                  : '无文字任务')
                            : task.text;
                        final busy = _busyId == task.id;
                        final steering = task.placement == 'steering';
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: steering
                                ? P.accent.withValues(alpha: 0.08)
                                : P.fillSubtle,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: steering
                                  ? P.accent.withValues(alpha: 0.35)
                                  : P.divider,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: P.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: P.accentLight,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: P.textTertiary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      content,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (task.imageCount > 0 &&
                                        task.text.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '附带 ${task.imageCount} 张图片',
                                          style: TextStyle(
                                            color: P.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (task.placement == 'queued')
                                PopupMenuButton<String>(
                                  tooltip: '任务操作',
                                  enabled: !busy,
                                  icon: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.more_vert),
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      unawaited(_edit(task));
                                    } else if (value == 'remove') {
                                      unawaited(_remove(task));
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      enabled: task.imageCount == 0,
                                      child: Text(
                                        task.imageCount == 0
                                            ? '编辑任务'
                                            : '含图片任务暂不支持编辑',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('删除任务'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

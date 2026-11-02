/// Chat message rendering, tool cards, and image previews.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:gal/gal.dart';

import 'src/theme.dart';
import 'src/tool_diff.dart';
import 'state.dart';

class ChatItemView extends StatelessWidget {
  const ChatItemView({
    super.key,
    required this.state,
    required this.item,
    this.animate = false,
  });

  final AppState state;
  final ChatItem item;

  /// Fresh arrivals play a short fade-and-rise entrance; history restores
  /// and page prepends render statically.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (item.kind) {
      ChatItemKind.user => _UserBubble(state: state, item: item),
      ChatItemKind.assistant => _AssistantMessage(state: state, item: item),
      ChatItemKind.tool =>
        item.images.isEmpty
            ? ToolCard(state: state, item: item)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ToolImageResult(state: state, item: item),
                  ToolCard(state: state, item: item),
                ],
              ),
      ChatItemKind.notice => _NoticeCard(state: state, item: item),
    };
    if (!animate) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: body,
    );
  }
}

/// Right-aligned gradient user bubble; long-press pops the copy action.
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: GestureDetector(
          onLongPressStart: (details) =>
              _showCopyMenu(context, details.globalPosition, item.text),
          child: Container(
            margin: const EdgeInsets.only(
              left: 56,
              right: 12,
              top: 5,
              bottom: 5,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              gradient: P.brandGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
              border: Border.all(color: P.onAccent.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: P.accent.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Opacity(
              opacity: item.provisional ? 0.65 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.images.isNotEmpty)
                    _ImageStrip(state: state, images: item.images),
                  if (item.text.isNotEmpty)
                    Text(
                      item.text,
                      style: TextStyle(
                        color: P.onAccent,
                        fontSize: 15.5,
                        height: 1.45,
                        fontFamily: item.text.startsWith('/')
                            ? 'monospace'
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// QQ-style long-press popup offering a single copy action.
void _showCopyMenu(BuildContext context, Offset position, String text) {
  HapticFeedback.selectionClick();
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: 'copy',
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 16, color: P.textSecondary),
            const SizedBox(width: 8),
            const Text('复制'),
          ],
        ),
      ),
    ],
  ).then((value) {
    if (value != 'copy' || !context.mounted) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  });
}

/// Full-width assistant message with avatar and markdown body.
class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  bool get _streaming => item.id.startsWith('stream-');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (item.images.isNotEmpty) {
      children.add(_ImageStrip(state: state, images: item.images));
      children.add(const SizedBox(height: 8));
    }
    for (final block in item.blocks) {
      if (block.type == 'reasoning') {
        children.add(_ReasoningCard(text: block.text, streaming: _streaming));
      } else if (block.text.trim().isNotEmpty || !_streaming) {
        children.add(
          MarkdownBody(
            data: block.text,
            selectable: true,
            styleSheet: _markdownStyle(context),
          ),
        );
      }
    }
    if (_streaming) {
      children.add(
        const Padding(padding: EdgeInsets.only(top: 6), child: _TypingDots()),
      );
    }
    if (item.interrupted) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: MiniChip(
            icon: Icons.stop_circle_outlined,
            label: '已中断',
            color: Colors.orange,
          ),
        ),
      );
    }
    final copyable = item.blocks
        .where((b) => b.type == 'text' && b.text.trim().isNotEmpty)
        .map((b) => b.text)
        .join('\n\n');
    if (!_streaming && copyable.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyable));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制回复内容'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.copy_rounded, size: 14, color: P.textTertiary),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: P.brandGradient,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: P.accent.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.auto_awesome, color: P.onAccent, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final base = TextStyle(
    color: scheme.onSurface.withValues(alpha: 0.92),
    fontSize: 15.5,
    height: 1.55,
  );
  return MarkdownStyleSheet(
    p: base,
    h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
    h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.bold),
    h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    h4: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    blockSpacing: 10,
    listIndent: 22,
    listBullet: base,
    listBulletPadding: const EdgeInsets.only(right: 6),
    strong: base.copyWith(fontWeight: FontWeight.bold),
    em: base.copyWith(fontStyle: FontStyle.italic),
    a: base.copyWith(color: P.accentLight),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      color: P.accentLight,
      backgroundColor: P.code,
    ),
    codeblockDecoration: BoxDecoration(
      color: P.code,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: P.fillLight),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: base.copyWith(color: P.textSecondary),
    blockquoteDecoration: BoxDecoration(
      color: P.fillSubtle,
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: P.accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    tableBorder: TableBorder.all(color: P.textTertiary, width: 0.5),
    tableHead: base.copyWith(fontWeight: FontWeight.bold),
    tableBody: base.copyWith(fontSize: 14),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: P.fillMedium)),
    ),
  );
}

/// Animated three-dot streaming indicator.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase =
                _controller.value * 2 * math.pi + i * (2 * math.pi / 3);
            final opacity = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(phase));
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: P.accentLight.withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Collapsible reasoning block.
class _ReasoningCard extends StatefulWidget {
  const _ReasoningCard({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  late bool _expanded = widget.streaming;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_alt_outlined,
                    size: 16,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.streaming ? '正在思考…' : '思考过程',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.amber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.amber.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          widget.text,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: P.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small label chip used for message metadata.
class MiniChip extends StatelessWidget {
  const MiniChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tool cards
// ---------------------------------------------------------------------------

class _ToolImageResult extends StatelessWidget {
  const _ToolImageResult({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 16, color: P.accentLight),
              const SizedBox(width: 6),
              Text(
                '图片结果',
                style: TextStyle(
                  color: P.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '来自 ${item.name}',
                style: TextStyle(color: P.textTertiary, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ImageStrip(state: state, images: item.images),
        ],
      ),
    );
  }
}

/// Status strip on a tool card's leading edge; pulses while the tool runs.
class _StatusStrip extends StatefulWidget {
  const _StatusStrip({required this.color, required this.running});

  final Color color;
  final bool running;

  @override
  State<_StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<_StatusStrip>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.running) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Container(width: 3, color: widget.color);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Container(
        width: 3,
        color: widget.color.withValues(alpha: 0.45 + 0.55 * controller.value),
      ),
    );
  }
}

class ToolCard extends StatefulWidget {
  const ToolCard({super.key, required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _expanded = false;

  Color get _statusColor {
    if (!widget.item.completed) return Colors.amber;
    if (widget.item.resultIsError) return P.danger;
    return P.success;
  }

  String get _statusLabel {
    if (!widget.item.completed) return '运行中';
    if (widget.item.resultIsError) return '失败';
    return '完成';
  }

  IconData get _icon {
    final name = widget.item.name.toLowerCase();
    if (name.contains('bash') ||
        name.contains('shell') ||
        name.contains('terminal')) {
      return Icons.terminal_rounded;
    }
    if (name.contains('read')) return Icons.description_outlined;
    if (name.contains('edit') || name.contains('write')) {
      return Icons.edit_note;
    }
    if (name.contains('grep') ||
        name.contains('glob') ||
        name.contains('search')) {
      return Icons.search;
    }
    if (name.contains('web') || name.contains('fetch')) return Icons.public;
    if (name.contains('todo')) return Icons.checklist;
    if (name.contains('agent')) return Icons.smart_toy_outlined;
    if (name.contains('skill')) return Icons.auto_awesome;
    return Icons.build_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final diff = parseToolDiff(item.name, item.arguments);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: P.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.fillLight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusStrip(color: _statusColor, running: !item.completed),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Icon(_icon, size: 16, color: P.textSecondary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (diff != null)
                                    Text(
                                      diff.path,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: P.textTertiary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            MiniChip(
                              icon: item.completed
                                  ? (item.resultIsError
                                        ? Icons.error_outline
                                        : Icons.check_circle_outline)
                                  : Icons.hourglass_top,
                              label: _statusLabel,
                              color: _statusColor,
                            ),
                            const Spacer(),
                            Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: P.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expanded) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (diff != null)
                              _diffSection(diff)
                            else if (item.arguments.isNotEmpty)
                              _codeSection(
                                '参数',
                                _truncate(summarizeArguments(item.arguments)),
                              ),
                            if (item.resultText != null) ...[
                              const SizedBox(height: 10),
                              _codeSection(
                                item.resultIsError ? '错误' : '结果',
                                _truncate(item.resultText!),
                                isError: item.resultIsError,
                              ),
                            ],
                            if (!item.completed)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '等待结果…',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: P.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeSection(String label, String content, {bool isError = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1,
            color: isError ? P.danger : P.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: P.code,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isError ? P.danger.withValues(alpha: 0.35) : P.fillLight,
            ),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: isError
                  ? P.danger.withValues(alpha: 0.9)
                  : P.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// Compact diff for `edit` / `write`: only the changed lines, like the web
  /// client (see `src/tool_diff.dart`). The raw argument JSON — which repeats
  /// the whole replaced block — is never the primary view for these tools.
  Widget _diffSection(ToolDiff diff) {
    const maxLines = 160;
    final lines = diff.lines;
    final shown = lines.length > maxLines
        ? lines.sublist(0, maxLines)
        : lines;
    bool isRemoved(ToolDiffLine line) => line.kind == ToolDiffKind.removed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              diff.isCreate ? '新建文件' : '变更',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                color: P.textTertiary,
              ),
            ),
            const Spacer(),
            if (!diff.isCreate)
              Text(
                '+${diff.addedLines.length}  −${diff.removedLines.length}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: P.textTertiary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: P.code,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: P.fillLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in shown)
                Container(
                  color: isRemoved(line)
                      ? P.danger.withValues(alpha: 0.10)
                      : P.success.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  child: SelectableText(
                    '${isRemoved(line) ? '−' : '+'} ${line.text}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.4,
                      color: isRemoved(line)
                          ? P.danger.withValues(alpha: 0.95)
                          : P.success,
                    ),
                  ),
                ),
              if (lines.length > maxLines)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '… 还有 ${lines.length - maxLines} 行（已截断）',
                    style: TextStyle(fontSize: 11, color: P.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _truncate(String text, [int max = 4000]) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n… (已截断)';
  }
}

/// System notice row (todo lists, errors, agent notices).
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.state, required this.item});

  final AppState state;
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isError
        ? P.danger
        : item.pending
        ? P.accentLight
        : P.textTertiary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: item.isError
            ? P.danger.withValues(alpha: 0.08)
            : item.pending
            ? P.accent.withValues(alpha: 0.08)
            : P.fillSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isError
              ? P.danger.withValues(alpha: 0.3)
              : item.pending
              ? P.accent.withValues(alpha: 0.3)
              : P.fillLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.pending)
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(P.accentLight),
                ),
              ),
            )
          else
            Icon(
              item.isError ? Icons.error_outline : Icons.checklist_rtl,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: color),
            ),
          ),
          if (item.retryText != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: state.selectedRunning
                    ? null
                    : () => state.sendPrompt(item.retryText!),
                child: const Text('重试'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.state, required this.images});

  final AppState state;
  final List<ChatImage> images;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: images.isNotEmpty ? 8 : 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final image in images)
            _ChatImageTile(state: state, image: image),
        ],
      ),
    );
  }
}

class _ChatImageTile extends StatefulWidget {
  const _ChatImageTile({required this.state, required this.image});

  final AppState state;
  final ChatImage image;

  @override
  State<_ChatImageTile> createState() => _ChatImageTileState();
}

class _ChatImageTileState extends State<_ChatImageTile> {
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.image.data == null) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final data = await widget.state.loadAttachment(widget.image);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = data == null;
    });
  }

  Uint8List? get _bytes {
    final data = widget.image.data;
    if (data == null) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return GestureDetector(
      onTap: bytes == null
          ? _load
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ImagePreviewPage(bytes: bytes, name: widget.image.name),
              ),
            ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: P.fillMedium),
          boxShadow: P.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 156,
            height: 156,
            color: P.fillLight,
            alignment: Alignment.center,
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : _loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: P.textTertiary,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _failed
                            ? Icons.broken_image_outlined
                            : Icons.image_outlined,
                        color: P.textTertiary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _failed ? '加载失败,点击重试' : '点击加载',
                        style: TextStyle(color: P.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({super.key, required this.bytes, this.name});

  final Uint8List bytes;
  final String? name;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final album = 'xHarness';
      await Gal.putImageBytes(widget.bytes, album: album);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已保存到系统相册')));
    } on GalException catch (error) {
      if (!mounted) return;
      final message = error.type == GalExceptionType.accessDenied
          ? '没有相册权限，请在系统设置中允许 xHarness 访问照片'
          : '保存图片失败，请稍后重试';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存图片失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.name ?? '图片预览'),
        actions: [
          IconButton(
            tooltip: '下载图片',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(widget.bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

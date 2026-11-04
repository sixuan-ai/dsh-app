/// Server-driven question interaction dialog.
library;

import 'package:flutter/material.dart';

import 'src/theme.dart';
import 'src/ui/glass.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Question dialog
// ---------------------------------------------------------------------------

class QuestionDialog extends StatefulWidget {
  const QuestionDialog({
    super.key,
    required this.state,
    required this.pending,
    this.onClosed,
  });

  final AppState state;
  final PendingQuestion pending;

  /// Close route owned by the interaction host (_showInteraction); when set,
  /// _submit uses it instead of a raw pop so the auto-close latch wins.
  final VoidCallback? onClosed;

  @override
  State<QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<QuestionDialog> {
  final Map<String, Set<String>> _selected = {};
  final Map<String, TextEditingController> _custom = {};

  @override
  void dispose() {
    for (final controller in _custom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _questionId(Map<String, dynamic> q) => q['id'] as String? ?? '';

  List<Map<String, dynamic>> _options(Map<String, dynamic> q) =>
      ((q['options'] as List?) ?? const [])
          .map((o) => (o as Map).cast<String, dynamic>())
          .toList();

  bool _multi(Map<String, dynamic> q) => q['multiSelect'] == true;

  TextEditingController _customFor(String id) =>
      _custom.putIfAbsent(id, TextEditingController.new);

  bool get _canSubmit {
    for (final q in widget.pending.questions) {
      final id = _questionId(q);
      final selected = _selected[id] ?? const <String>{};
      final custom = _custom[id]?.text.trim() ?? '';
      if (selected.isEmpty && custom.isEmpty) return false;
    }
    return true;
  }

  void _toggle(String id, String label, bool multi) {
    setState(() {
      final set = _selected.putIfAbsent(id, () => {});
      if (multi) {
        set.contains(label) ? set.remove(label) : set.add(label);
      } else {
        set
          ..clear()
          ..add(label);
      }
    });
  }

  void _submit() {
    final answers = <Map<String, dynamic>>[
      for (final q in widget.pending.questions)
        {
          'id': _questionId(q),
          'selected': (_selected[_questionId(q)] ?? const <String>{}).toList(),
          if ((_custom[_questionId(q)]?.text.trim() ?? '').isNotEmpty)
            'custom': _custom[_questionId(q)]!.text.trim(),
        },
    ];
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed();
    } else {
      Navigator.of(context).pop();
    }
    widget.state.answerQuestion(widget.pending, answers);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.quiz_outlined, color: P.warning),
          SizedBox(width: 10),
          Text('请回答'),
        ],
      ),
      content: GlassPanel(
        tint: P.warning.withValues(alpha: .35),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.pending.questions.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  _questionView(widget.pending.questions[i]),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('提交'),
        ),
      ],
    );
  }

  Widget _questionView(Map<String, dynamic> q) {
    final id = _questionId(q);
    final header = q['header'] as String?;
    final question = q['question'] as String? ?? '';
    final detail = q['detail'] as String?;
    final options = _options(q);
    final multi = _multi(q);
    final selected = _selected[id] ?? const <String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null && header.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: P.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                header,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.4,
                  color: P.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
        if (detail != null && detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              detail,
              style: TextStyle(
                fontSize: 12.5,
                color: P.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        if (multi)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '可多选',
              style: TextStyle(fontSize: 11, color: P.textTertiary),
            ),
          ),
        const SizedBox(height: 10),
        for (final option in options)
          _optionTile(
            id,
            option,
            multi,
            selected.contains(option['label'] as String? ?? ''),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextField(
            controller: _customFor(id),
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: options.isEmpty ? '输入回答' : '其他(可选)',
              hintStyle: TextStyle(fontSize: 13, color: P.textTertiary),
              isDense: true,
              filled: true,
              fillColor: P.fillSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: P.fillLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: P.fillLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: P.accent.withValues(alpha: 0.65),
                  width: 1.2,
                ),
              ),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
    String id,
    Map<String, dynamic> option,
    bool multi,
    bool selected,
  ) {
    final label = option['label'] as String? ?? '';
    final description = option['description'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggle(id, label, multi),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? P.warning.withValues(alpha: .12) : P.fillSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? P.accent.withValues(alpha: 0.4) : P.fillMedium,
            ),
          ),
          child: Row(
            children: [
              Icon(
                multi
                    ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                    : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off),
                size: 20,
                color: selected ? P.accentLight : P.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : null,
                        color: selected ? P.accentLight : null,
                      ),
                    ),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description,
                          style: TextStyle(fontSize: 12, color: P.textTertiary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

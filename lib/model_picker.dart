/// Model selection sheet and reasoning-effort picker.
library;

import 'package:flutter/material.dart';

import 'chat_view.dart';
import 'src/theme.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Model picker
// ---------------------------------------------------------------------------

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({super.key, required this.state});

  final AppState state;

  bool _isCurrent(String provider, String model) {
    final current = state.models?.current ?? const {};
    return current['provider'] == provider && current['model'] == model;
  }

  Future<void> _pick(
    BuildContext context,
    String provider,
    Map<String, dynamic> model,
  ) async {
    final modelId = model['id'] as String? ?? '';
    if (modelId.isEmpty) return;
    final reasoning = (model['reasoning'] as Map?)?.cast<String, dynamic>();
    final efforts = ((reasoning?['efforts'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    String? effort;
    if (efforts.isNotEmpty) {
      effort = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('推理强度'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('默认'),
            ),
            for (final e in efforts)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(e['id'] as String? ?? ''),
                child: Text(e['name'] as String? ?? e['id'] as String? ?? ''),
              ),
          ],
        ),
      );
      // Dismissed without a choice: leave the selection untouched.
      if (effort == null) return;
    }
    if (!context.mounted) return;
    final name = model['name'] as String? ?? modelId;
    final chosenEffort = (effort == null || effort.isEmpty) ? null : effort;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.selectModel(provider, modelId, reasoningEffort: chosenEffort);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            chosenEffort == null
                ? '已切换模型: $name'
                : '已切换模型: $name · 推理强度 $chosenEffort',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('切换失败: $error'),
          backgroundColor: P.danger,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = state.models;
    if (models == null) {
      return const SizedBox(height: 200, child: Center(child: Text('模型目录不可用')));
    }
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '选择模型',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (models.current['model'] != null)
                      Text(
                        '当前: ${models.label}',
                        style: TextStyle(fontSize: 12, color: P.textTertiary),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final group in models.groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      (group['name'] as String? ?? group['id'] as String? ?? '')
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                        color: P.accentLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final model
                      in ((group['models'] as List?) ?? const []).map(
                        (m) => (m as Map).cast<String, dynamic>(),
                      ))
                    _modelTile(context, group['id'] as String? ?? '', model),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modelTile(
    BuildContext context,
    String provider,
    Map<String, dynamic> model,
  ) {
    final id = model['id'] as String? ?? '';
    final name = model['name'] as String? ?? id;
    final description = model['description'] as String?;
    final current = _isCurrent(provider, id);
    final reasoning = (model['reasoning'] as Map?)?.cast<String, dynamic>();
    final hasEfforts =
        ((reasoning?['efforts'] as List?) ?? const []).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: current
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
            : P.fillSubtle,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            name,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: current ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                id,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: P.textTertiary,
                ),
              ),
              if (description != null && description.isNotEmpty)
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: P.textTertiary),
                ),
              if (current &&
                  (state.models?.current['reasoningEffort'] as String? ?? '')
                      .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: MiniChip(
                    icon: Icons.tune,
                    label: '推理强度 ${state.models!.current['reasoningEffort']}',
                    color: P.accentLight,
                  ),
                ),
            ],
          ),
          trailing: current
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                )
              : hasEfforts
              ? Icon(Icons.tune, size: 18, color: P.textTertiary)
              : null,
          onTap: () => _pick(context, provider, model),
        ),
      ),
    );
  }
}

/// Text input and send controls for the chat composer.
library;

import 'package:flutter/material.dart';
import 'src/theme.dart';

class ComposerInput extends StatelessWidget {
  const ComposerInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.canSend,
    required this.running,
    required this.picking,
    required this.canPickImage,
    required this.onChanged,
    required this.onOpenCommands,
    required this.onPickImage,
    required this.onStop,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool canSend;
  final bool running;
  final bool picking;
  final bool canPickImage;
  final ValueChanged<String> onChanged;
  final VoidCallback onOpenCommands;
  final VoidCallback onPickImage;
  final VoidCallback onStop;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: IconButton(
            tooltip: '快捷命令',
            icon: const Icon(Icons.add_circle_outline),
            color: P.textSecondary,
            onPressed: enabled ? onOpenCommands : null,
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            enabled: enabled,
            minLines: 1,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(fontSize: 15.5),
            decoration: InputDecoration(
              hintText: enabled ? '发消息给 DSH…' : '先选择或新建一个会话',
              hintStyle: TextStyle(color: P.textTertiary),
              border: InputBorder.none,
            ),
          ),
        ),
        if (running)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: Container(
              decoration: BoxDecoration(
                color: P.danger.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: P.danger.withValues(alpha: 0.5)),
              ),
              child: IconButton(
                tooltip: '停止生成',
                icon: Icon(Icons.stop_rounded, color: P.danger),
                onPressed: onStop,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: IconButton(
            tooltip: '添加图片',
            icon: picking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_outlined),
            color: P.textSecondary,
            onPressed: enabled && canPickImage ? onPickImage : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Container(
            decoration: BoxDecoration(
              gradient: canSend ? P.brandGradient : null,
              color: canSend ? null : P.fillLight,
              shape: BoxShape.circle,
              boxShadow: canSend ? [P.brandGlow] : null,
            ),
            child: IconButton(
              tooltip: '发送',
              icon: Icon(
                Icons.arrow_upward_rounded,
                color: canSend ? P.onAccent : P.textTertiary,
              ),
              onPressed: canSend ? onSend : null,
            ),
          ),
        ),
      ],
    );
  }
}

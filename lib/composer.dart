/// Chat composer, quick commands, images, and permission controls.
library;

import 'access_policy.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'composer_input.dart';
import 'src/prompt_image_normalizer.dart';
import 'src/theme.dart';
import 'src/l10n.dart';
import 'state.dart';

class Composer extends StatefulWidget {
  const Composer({super.key, required this.state});

  final AppState state;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<PromptImage> _images = [];
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openCommands() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Without this the sheet caps at half the screen and the sheet's own
      // column cannot scroll, so long server catalogs (e.g. /permission at
      // the tail) were clipped away with no way to reach them.
      isScrollControlled: true,
      builder: (sheetContext) => _CommandsSheet(
        state: widget.state,
        onRun: (command) {
          Navigator.of(sheetContext).pop();
          widget.state.runCommand('/$command');
        },
        onOpenPermissions: () {
          Navigator.of(sheetContext).pop();
          _openPermissions();
        },
        onInsert: (command) {
          Navigator.of(sheetContext).pop();
          _controller.text = '/$command ';
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
          _focusNode.requestFocus();
        },
      ),
    );
  }

  Future<void> _pickImage() async {
    if (_picking || _images.length >= 4) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final encoded = await compute(normalizePromptImage, bytes);
      if (encoded.bytes.length > 8 * 1024 * 1024) {
        throw StateError('图片超过 8 MB,请换一张');
      }
      if (!mounted) return;
      setState(() {
        _images.add(
          PromptImage(
            mediaType: 'image/jpeg',
            data: base64Encode(encoded.bytes),
            name: picked.name,
            width: encoded.width,
            height: encoded.height,
          ),
        );
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $error')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openPermissions() =>
      showPermissionPicker(context, widget.state);

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    final images = List<PromptImage>.of(_images);
    _controller.clear();
    setState(() => _images.clear());
    HapticFeedback.lightImpact();
    if (text.startsWith('/') && images.isEmpty) {
      // Slash commands render their own echo + progress + result in chat.
      widget.state.runCommand(text);
      return;
    }
    final sent = await widget.state.sendPrompt(text, images: images);
    if (!sent && mounted) {
      setState(() {
        if (_controller.text.isEmpty) _controller.text = text;
        _images.insertAll(0, images);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cached conversations remain readable while disconnected, but sending a
    // prompt or opening a command sheet must wait until the host is back.
    final enabled =
        widget.state.selectedSessionId != null && widget.state.serverAvailable;
    final focused = _focusNode.hasFocus;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: P.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: focused
                  ? P.accent.withValues(alpha: 0.65)
                  : (P.isDark ? P.fillMedium : P.divider),
              width: focused ? 1.2 : 1,
            ),
            boxShadow: focused ? [...P.cardShadow, P.brandGlow] : P.cardShadow,
          ),
          padding: const EdgeInsets.only(left: 4, right: 6, top: 5, bottom: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_images.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 10, bottom: 5),
                      itemCount: _images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final image = _images[index];
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(image.data),
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.cancel, size: 19),
                                color: P.danger,
                                onPressed: () =>
                                    setState(() => _images.removeAt(index)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => ComposerInput(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: enabled,
                  canSend:
                      enabled &&
                      (value.text.trim().isNotEmpty || _images.isNotEmpty),
                  running: widget.state.selectedRunning,
                  picking: _picking,
                  canPickImage: !_picking && _images.length < 4,
                  onChanged: (_) {},
                  onOpenCommands: _openCommands,
                  onPickImage: _pickImage,
                  onStop: widget.state.cancelTurn,
                  onSend: _send,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slash command offered by the composer sheet.
class _SlashCommand {
  const _SlashCommand(
    this.name,
    this.icon,
    this.description, {
    this.hasInput = false,
  });

  final String name;
  final IconData icon;
  final String description;

  /// Commands with input insert the prefix instead of sending directly.
  final bool hasInput;
}

const _slashCommands = [
  _SlashCommand('compact', Icons.compress, '压缩较早的对话历史,释放上下文空间'),
  _SlashCommand('plan', Icons.map_outlined, '进入或退出计划模式'),
  _SlashCommand('goal', Icons.flag_outlined, '设置或查看长期任务目标', hasInput: true),
  _SlashCommand(
    'feedback',
    Icons.rate_review_outlined,
    '记录对本会话的反馈',
    hasInput: true,
  ),
];

/// Both the composer and drawer use the same picker and confirmation flow.
Future<void> showPermissionPicker(BuildContext context, AppState state) async {
  final sessionId = state.selectedSessionId;
  if (sessionId == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('先选择或新建一个会话')));
    return;
  }
  final preset = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => PermissionSheet(
        currentPreset:
            state.projectionOf(sessionId, 'permissions')?['currentValue']
                as String?,
        onPick: (value) => Navigator.of(sheetContext).pop(value),
      ),
    ),
  );
  if (preset == null ||
      !context.mounted ||
      state.selectedSessionId != sessionId) {
    return;
  }
  if (preset == 'danger-full-access') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.enableFullAccess),
        content: Text(S.fullAccessWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.enable),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        state.selectedSessionId != sessionId) {
      return;
    }
  }
  await state.runCommand('/permission $preset');
}

/// Permission-mode sheet (drawer → 权限模式): one tap per preset; the pick
/// rides the /permission command, so the chat shows the usual command card.
class PermissionSheet extends StatelessWidget {
  const PermissionSheet({super.key, required this.onPick, this.currentPreset});

  final String? currentPreset;

  /// Called with the chosen preset name ('workspace-write' etc.).
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '权限模式',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '控制当前会话的文件访问范围与审批策略。$kComputerPermissionSummary',
              style: TextStyle(fontSize: 12, color: P.textTertiary),
            ),
            const SizedBox(height: 12),
            _PermissionOption(
              icon: Icons.edit_note,
              title: '工作区写入',
              preset: 'workspace-write',
              selected: currentPreset == 'workspace-write',
              description: '只能写当前工作区;越权操作会先弹审批询问你',
              onPick: onPick,
            ),
            const SizedBox(height: 6),
            _PermissionOption(
              icon: Icons.lock_open_outlined,
              title: '完全访问',
              preset: 'danger-full-access',
              selected: currentPreset == 'danger-full-access',
              description: '全部文件可读写,且不再弹审批(需二次确认)',
              danger: true,
              onPick: onPick,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionOption extends StatelessWidget {
  const _PermissionOption({
    required this.icon,
    required this.title,
    required this.preset,
    required this.description,
    required this.onPick,
    this.danger = false,
    this.selected = false,
  });

  final IconData icon;
  final String title;

  /// Preset name passed to /permission.
  final String preset;
  final String description;
  final ValueChanged<String> onPick;

  /// Danger presets (full device access) use a warning icon treatment.
  final bool danger;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: P.fillSubtle,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: danger ? null : P.brandGradient,
            color: danger ? P.danger.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(10),
            border: danger
                ? Border.all(color: P.danger.withValues(alpha: 0.4))
                : null,
          ),
          child: Icon(icon, size: 18, color: danger ? P.danger : P.onAccent),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          description,
          style: TextStyle(fontSize: 12, color: P.textSecondary),
        ),
        trailing: selected ? const Chip(label: Text('当前')) : null,
        onTap: () => onPick(preset),
      ),
    );
  }
}

/// Quick-command sheet opened from the composer's + button. The catalog
/// loads live from the host (commands/list); the built-in list is the
/// offline fallback.
class _CommandsSheet extends StatefulWidget {
  const _CommandsSheet({
    required this.state,
    required this.onRun,
    required this.onInsert,
    required this.onOpenPermissions,
  });

  final AppState state;

  /// Executes `/<name>` immediately.
  final ValueChanged<String> onRun;

  /// Inserts `/<name> ` into the composer for argument entry.
  final ValueChanged<String> onInsert;

  /// Opens the current session's permission preset picker.
  final VoidCallback onOpenPermissions;

  @override
  State<_CommandsSheet> createState() => _CommandsSheetState();
}

class _CommandsSheetState extends State<_CommandsSheet> {
  List<_SlashCommand> _commands = _slashCommands;

  static const _icons = <String, IconData>{
    'compact': Icons.compress,
    'plan': Icons.map_outlined,
    'goal': Icons.flag_outlined,
    'feedback': Icons.rate_review_outlined,
    'export': Icons.download_outlined,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.state.listCommands();
      if (!mounted || catalog.isEmpty) return;
      setState(() {
        _commands = [
          for (final entry in catalog)
            if (entry['name'] != 'permission')
              _SlashCommand(
                entry['name'] as String? ?? '',
                _icons[entry['name']] ?? Icons.terminal,
                entry['description'] as String? ?? '',
                hasInput: entry['input'] != null,
              ),
        ];
      });
    } catch (_) {
      // Keep the built-in fallback list.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快捷命令',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '以 / 开头的消息会作为命令执行,不会发送给模型',
              style: TextStyle(fontSize: 12, color: P.textTertiary),
            ),
            const SizedBox(height: 12),
            Material(
              color: P.fillSubtle,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: P.isDark
                        ? P.success.withValues(alpha: 0.18)
                        : P.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: P.success,
                  ),
                ),
                title: const Text(
                  '权限模式',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '切换工作区写入或完全访问',
                  style: TextStyle(fontSize: 12, color: P.textSecondary),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: P.textTertiary,
                ),
                onTap: widget.onOpenPermissions,
              ),
            ),
            const SizedBox(height: 12),
            // Bounded, scrollable list: the catalog comes from the server and
            // grows over time; a fixed Column clipped past the sheet height.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final command in _commands)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: P.fillSubtle,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: P.brandGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              command.icon,
                              size: 18,
                              color: P.onAccent,
                            ),
                          ),
                          title: Text(
                            '/${command.name}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            command.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: P.textSecondary,
                            ),
                          ),
                          trailing: Icon(
                            command.hasInput
                                ? Icons.edit_outlined
                                : Icons.play_arrow_rounded,
                            size: 18,
                            color: P.textTertiary,
                          ),
                          onTap: () => command.hasInput
                              ? widget.onInsert(command.name)
                              : widget.onRun(command.name),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

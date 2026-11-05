/// New-session workspace and remote folder selection.
library;

import 'package:flutter/material.dart';

import 'folder_picker_page.dart';
import 'src/theme.dart';
import 'state.dart';

class NewSessionSheet extends StatefulWidget {
  const NewSessionSheet({super.key, required this.state});
  final AppState state;

  @override
  State<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<NewSessionSheet> {
  String _selection = 'default';
  String? _workspaceId;
  String? _pickedPath;
  final _customPath = TextEditingController();
  bool _creating = false;
  String? _error;
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.loadWorkspaces();
    _customPath.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _customPath.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FolderPickerPage(
          directoryLoader: state.listDirectory,
          createDirectory: state.createDirectory,
          initialPath: _pickedPath,
          onManualInput: () {
            if (mounted) setState(() => _selection = 'manual');
          },
        ),
      ),
    );
    if (mounted && path != null) {
      setState(() {
        _pickedPath = path;
        _selection = 'browse';
      });
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await state.createSession(
        workspaceId: _selection == 'workspace' ? _workspaceId : null,
        cwd: _selection == 'manual'
            ? _customPath.text.trim()
            : _selection == 'browse'
            ? _pickedPath
            : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = '$error';
        });
      }
    }
  }

  Widget _row(
    String title,
    bool selected,
    VoidCallback onTap, {
    String? subtitle,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          onTap: _creating ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? P.accent.withValues(alpha: 0.10) : P.fillSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? P.accent.withValues(alpha: 0.35)
                    : P.fillLight,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: selected ? P.accentLight : P.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14)),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: P.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 18, color: P.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新建会话',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _row(
                '默认工作区',
                _selection == 'default',
                () => setState(() => _selection = 'default'),
                subtitle: '使用服务器的默认目录',
              ),
              if (state.loadingWorkspaces)
                const Center(child: CircularProgressIndicator()),
              for (final workspace in state.workspaces)
                _row(
                  workspace['title'] as String? ?? '',
                  _selection == 'workspace' &&
                      _workspaceId == workspace['workspaceId'],
                  () => setState(() {
                    _selection = 'workspace';
                    _workspaceId = workspace['workspaceId'] as String;
                  }),
                  subtitle:
                      "${workspace['path'] ?? ''}\n${(workspace['sessionIds'] as List?)?.length ?? 0} 个会话",
                ),
              _row(
                _pickedPath == null ? '浏览电脑文件夹…' : '已选择：$_pickedPath',
                _selection == 'browse',
                _browse,
                icon: Icons.folder_outlined,
              ),
              _row(
                '手动输入路径',
                _selection == 'manual',
                () => setState(() => _selection = 'manual'),
                icon: Icons.edit_outlined,
              ),
              if (_selection == 'manual')
                TextField(
                  controller: _customPath,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '/home/you/project',
                    helperText: '必须是电脑上已存在的目录',
                    helperMaxLines: 3,
                    filled: true,
                    fillColor: P.fillSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              if (_error != null)
                Text(
                  '创建失败: $_error',
                  style: TextStyle(fontSize: 12.5, color: P.danger),
                ),
              const SizedBox(height: 16),
              _CreateSessionButton(
                label: '创建',
                loading: _creating,
                onPressed:
                    !_creating &&
                        (_selection != 'manual' ||
                            _customPath.text.trim().isNotEmpty)
                    ? _create
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CreateSessionButton extends StatelessWidget {
  const _CreateSessionButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}

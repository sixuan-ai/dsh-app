/// New-session workspace and custom-directory picker.
library;

import 'package:flutter/material.dart';

import 'src/theme.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// New-session directory picker
// ---------------------------------------------------------------------------

/// New-session sheet: create in the default workspace (checked by default),
/// or uncheck to pick a registered workspace / enter a custom directory.
class NewSessionSheet extends StatefulWidget {
  const NewSessionSheet({super.key, required this.state});

  final AppState state;

  @override
  State<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<NewSessionSheet> {
  bool _useDefault = true;
  String? _selectedWorkspaceId;
  bool _customMode = false;
  final TextEditingController _customPath = TextEditingController();
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

  bool get _canCreate {
    if (_creating) return false;
    if (_useDefault) return true;
    if (_customMode) return _customPath.text.trim().isNotEmpty;
    return _selectedWorkspaceId != null;
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      if (_useDefault) {
        await state.createSession();
      } else if (_customMode) {
        await state.createSession(cwd: _customPath.text.trim());
      } else {
        await state.createSession(workspaceId: _selectedWorkspaceId);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Padding(
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
                  Row(
                    children: [
                      const Icon(Icons.add_comment_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '新建会话',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _defaultTile(),
                  if (!_useDefault) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        '选择工作区目录',
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 0.6,
                          color: P.accentLight,
                        ),
                      ),
                    ),
                    if (state.loadingWorkspaces)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      for (final workspace in state.workspaces)
                        _workspaceTile(workspace),
                      _customTile(),
                      if (state.workspaces.isEmpty && !_customMode)
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            '没有已注册的工作区,可使用自定义路径',
                            style: TextStyle(
                              fontSize: 12,
                              color: P.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '创建失败: $_error',
                      style: TextStyle(fontSize: 12.5, color: P.danger),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _CreateSessionButton(
                    label: '创建',
                    loading: _creating,
                    onPressed: _canCreate ? _create : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _useDefault = !_useDefault),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _useDefault
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
              : P.fillSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _useDefault
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                : P.fillLight,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _useDefault ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: _useDefault
                  ? Theme.of(context).colorScheme.primary
                  : P.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('在默认工作区创建', style: TextStyle(fontSize: 14)),
                  Text(
                    '使用服务器的默认目录',
                    style: TextStyle(fontSize: 11.5, color: P.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceTile(Map<String, dynamic> workspace) {
    final id = workspace['workspaceId'] as String? ?? '';
    final title = workspace['title'] as String? ?? '';
    final path = workspace['path'] as String? ?? '';
    final sessions = (workspace['sessionIds'] as List?)?.length ?? 0;
    final selected = !_customMode && _selectedWorkspaceId == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _customMode = false;
          _selectedWorkspaceId = id;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                : P.fillSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                  : P.fillLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : P.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    Text(
                      path,
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
              Text(
                '$sessions 个会话',
                style: TextStyle(fontSize: 11, color: P.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _customMode = true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _customMode
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.16)
                  : P.fillSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _customMode
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.6)
                    : P.fillLight,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _customMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: _customMode
                      ? Theme.of(context).colorScheme.primary
                      : P.textTertiary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('自定义路径', style: TextStyle(fontSize: 14)),
                ),
                Icon(Icons.edit_outlined, size: 16, color: P.textTertiary),
              ],
            ),
          ),
        ),
        if (_customMode)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _customPath,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: '/home/you/project',
                hintStyle: TextStyle(color: P.textTertiary),
                helperText: '必须是服务器上已存在的目录',
                helperStyle: TextStyle(fontSize: 11, color: P.textTertiary),
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
              ),
            ),
          ),
      ],
    );
  }
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

/// Read-only directory tree browser for the connected host.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/directory_listing.dart';
import 'src/theme.dart';

/// Lazily expanded directory tree over the host's `host.listDirectory` RPC.
class DirectoryTreePage extends StatefulWidget {
  const DirectoryTreePage({super.key, required this.directoryLoader});

  /// Loads one directory level; null path lists the host home directory.
  final Future<DirectoryListingView> Function(String? path) directoryLoader;

  @override
  State<DirectoryTreePage> createState() => _DirectoryTreePageState();
}

class _DirectoryTreePageState extends State<DirectoryTreePage> {
  /// Loaded level per directory path (the root lives under '').
  final Map<String, DirectoryListingView> _levels = {};
  final Set<String> _expanded = {};
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};
  bool _showHidden = false;

  static const _rootKey = '';

  @override
  void initState() {
    super.initState();
    _load(_rootKey, null);
  }

  Future<void> _load(String key, String? path) async {
    if (_loading.contains(key)) return;
    setState(() {
      _loading.add(key);
      _errors.remove(key);
    });
    try {
      final listing = await widget.directoryLoader(path);
      if (!mounted) return;
      setState(() => _levels[key] = listing);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors[key] = '$error');
    } finally {
      if (mounted) setState(() => _loading.remove(key));
    }
  }

  void _toggle(String key, String path) {
    if (_expanded.contains(key)) {
      setState(() => _expanded.remove(key));
      return;
    }
    setState(() => _expanded.add(key));
    if (!_levels.containsKey(key) && !_loading.contains(key)) {
      _load(key, path);
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('路径已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final root = _levels[_rootKey];
    return Scaffold(
      appBar: AppBar(
        title: const Text('目录浏览'),
        actions: [
          Row(
            children: [
              Text(
                '显示隐藏',
                style: TextStyle(fontSize: 12, color: P.textTertiary),
              ),
              Switch(
                value: _showHidden,
                onChanged: (value) => setState(() => _showHidden = value),
              ),
            ],
          ),
        ],
      ),
      body: root == null
          ? Center(
              child: _errors.containsKey(_rootKey)
                  ? _ErrorRetry(
                      error: _errors[_rootKey]!,
                      onRetry: () => _load(_rootKey, null),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              color: P.accent,
              backgroundColor: P.cardAlt,
              onRefresh: () async {
                _levels.clear();
                _errors.clear();
                await _load(_rootKey, null);
                for (final key in _expanded.toList()) {
                  final level = _levels[key];
                  if (level != null) await _load(key, level.path);
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: Text(
                      root.path,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: P.textTertiary,
                      ),
                    ),
                  ),
                  for (final entry in root.entries)
                    if (_showHidden || !entry.hidden)
                      ..._nodeRows(entry, depth: 0),
                  if (root.entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          '这个目录没有子目录',
                          style: TextStyle(color: P.textTertiary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  /// One directory row plus, when expanded, its subtree rows.
  List<Widget> _nodeRows(DirectoryEntryView entry, {required int depth}) {
    final key = entry.path;
    final expanded = _expanded.contains(key);
    final level = _levels[key];
    final error = _errors[key];
    final loading = _loading.contains(key);
    return [
      InkWell(
        onTap: () => _toggle(key, entry.path),
        onLongPress: () => _copyPath(entry.path),
        child: Padding(
          padding: EdgeInsets.only(
            left: 14 + depth * 18.0,
            right: 8,
            top: 9,
            bottom: 9,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: P.textTertiary,
                        ),
                      )
                    : Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: P.textTertiary,
                      ),
              ),
              Icon(
                expanded ? Icons.folder_open : Icons.folder_outlined,
                size: 19,
                color: expanded ? P.accentLight : P.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: entry.hidden ? P.textTertiary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (expanded && error != null)
        Padding(
          padding: EdgeInsets.only(left: 54 + depth * 18.0, right: 12),
          child: _ErrorRetry(
            error: error,
            onRetry: () => _load(key, entry.path),
          ),
        ),
      if (expanded && level != null) ...[
        if (level.truncated)
          Padding(
            padding: EdgeInsets.only(
              left: 54 + (depth + 1) * 18.0,
              top: 2,
              bottom: 6,
            ),
            child: Text(
              '子目录较多,仅显示前 ${level.entries.length} 个',
              style: TextStyle(fontSize: 11, color: P.textTertiary),
            ),
          ),
        for (final child in level.entries)
          if (_showHidden || !child.hidden)
            ..._nodeRows(child, depth: depth + 1),
        if (level.entries.isEmpty)
          Padding(
            padding: EdgeInsets.only(
              left: 54 + (depth + 1) * 18.0,
              top: 2,
              bottom: 6,
            ),
            child: Text(
              '空目录',
              style: TextStyle(fontSize: 11.5, color: P.textTertiary),
            ),
          ),
      ],
    ];
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '加载失败: $error',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: P.danger),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

/// Remote host folder selection.
library;

import 'package:flutter/material.dart';

import 'src/directory_listing.dart';
import 'src/protocol.dart';
import 'src/theme.dart';

class FolderPickerPage extends StatefulWidget {
  const FolderPickerPage({
    super.key,
    required this.directoryLoader,
    required this.createDirectory,
    this.initialPath,
    this.onManualInput,
  });

  final Future<DirectoryListingView> Function(String? path) directoryLoader;
  final Future<String> Function(String parent, String name) createDirectory;
  final String? initialPath;
  final VoidCallback? onManualInput;

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  DirectoryListingView? _listing;
  Object? _error;
  String? _requestedPath;
  bool _loading = true;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _load(widget.initialPath);
  }

  Future<void> _load(String? path) async {
    setState(() {
      _requestedPath = path;
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.directoryLoader(path);
      if (mounted) setState(() => _listing = listing);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newFolder() async {
    final parent = _listing!.path;
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    bool creating = false;
    String? error;
    late final DialogRoute<String> route;
    route = DialogRoute<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('新建文件夹'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    enabled: !creating,
                    decoration: const InputDecoration(
                      labelText: '文件夹名称',
                      errorMaxLines: 3,
                    ),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return '请输入文件夹名称';
                      if (name == '.' ||
                          name == '..' ||
                          name.contains('/') ||
                          name.contains('\\')) {
                        return '名称不能是 .、.. 或包含 /、\\';
                      }
                      return null;
                    },
                  ),
                  if (error != null)
                    Text(error!, style: TextStyle(color: P.danger)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: creating ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: creating
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      update(() {
                        creating = true;
                        error = null;
                      });
                      try {
                        final path = await widget.createDirectory(
                          parent,
                          controller.text.trim(),
                        );
                        if (context.mounted && route.isCurrent) {
                          Navigator.pop(context, path);
                        }
                      } catch (failure) {
                        if (context.mounted && route.isCurrent) {
                          update(() {
                            creating = false;
                            error = '$failure';
                          });
                        }
                      }
                    },
              child: Text(creating ? '创建中…' : '创建'),
            ),
          ],
        ),
      ),
    );
    final path = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (mounted && path != null) await _load(path);
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    final ready = !_loading && _error == null && listing != null;
    final error = _error;
    final unavailable =
        error is DshError &&
        (error.code == 'directory-picker/unavailable' ||
            error.code == 'directory-picker-unavailable');
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        title: const Text('选择文件夹'),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            onPressed: ready ? _newFolder : null,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('显示隐藏文件夹'),
              value: _showHidden,
              onChanged: (value) => setState(() => _showHidden = value),
            ),
            if (ready) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final (index, crumb) in listing.crumbs.indexed) ...[
                      if (index > 0)
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: P.textTertiary,
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _load(crumb.path),
                        child: Text(crumb.name),
                      ),
                    ],
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: listing.crumbs.length > 1
                      ? () => _load(
                          listing.crumbs[listing.crumbs.length - 2].path,
                        )
                      : null,
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('上一级'),
                ),
              ),
              if (listing.truncated)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('文件夹较多，仅显示部分结果'),
                ),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        color: P.fillSubtle,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                unavailable
                                    ? directoryBrowseUnavailableMessage
                                    : '加载失败：$error',
                              ),
                              const SizedBox(height: 12),
                              if (unavailable)
                                TextButton(
                                  onPressed: () {
                                    widget.onManualInput?.call();
                                    Navigator.pop(context);
                                  },
                                  child: const Text('改为手动输入路径'),
                                )
                              else
                                TextButton(
                                  onPressed: () => _load(_requestedPath),
                                  child: const Text('重试'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final entry in listing!.entries.where(
                          (entry) => _showHidden || !entry.hidden,
                        ))
                          ListTile(
                            leading: Icon(
                              Icons.folder_outlined,
                              color: P.accentLight,
                            ),
                            title: Text(entry.name),
                            onTap: () => _load(entry.path),
                          ),
                        if (listing.entries
                            .where((entry) => _showHidden || !entry.hidden)
                            .isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('此目录下没有文件夹'),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    listing?.path ?? '',
                    textDirection: TextDirection.ltr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: P.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: ready
                        ? () => Navigator.pop(context, listing.path)
                        : null,
                    child: const Text('选择此文件夹'),
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

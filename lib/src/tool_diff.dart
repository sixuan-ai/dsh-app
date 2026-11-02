/// Diff model for `edit` / `write` tool calls.
///
/// The web client renders these as a compact diff card: the file path plus the
/// lines that actually changed, never the raw JSON argument blob. This mirrors
/// that derivation so the phone shows the same thing.
library;

import 'dart:convert';

enum ToolDiffKind { added, removed }

class ToolDiffLine {
  const ToolDiffLine(this.text, this.kind);

  final String text;
  final ToolDiffKind kind;
}

class ToolDiff {
  const ToolDiff({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;

  /// Removed text; empty when the call creates a file.
  final String oldText;

  /// Added text.
  final String newText;

  bool get isCreate => oldText.isEmpty;

  List<String> get removedLines => splitLines(oldText);
  List<String> get addedLines => splitLines(newText);

  /// Visible hunks, in the order the card renders them.
  List<ToolDiffLine> get lines => [
    for (final line in removedLines)
      ToolDiffLine(line, ToolDiffKind.removed),
    for (final line in addedLines) ToolDiffLine(line, ToolDiffKind.added),
  ];

  /// Splits on newlines, dropping the trailing empty line a final `\n` creates.
  static List<String> splitLines(String text) {
    if (text.isEmpty) return const [];
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }
}

/// Derives the diff a tool call intends to make, or null when the call is not
/// one of the file-editing tools (or its arguments are malformed).
///
/// Mirrors the web client's `intendedDiff`: `edit` uses `old_string` /
/// `new_string`, `write` is a whole-file addition, and the str_replace_editor
/// create/replace commands behave like `write` / `edit`.
ToolDiff? parseToolDiff(String name, String rawArguments) {
  if (rawArguments.isEmpty) return null;
  final Map<String, dynamic> args;
  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is! Map) return null;
    args = decoded.cast<String, dynamic>();
  } catch (_) {
    return null;
  }

  String? str(String key) {
    final value = args[key];
    return value is String ? value : null;
  }

  switch (name) {
    case 'edit':
      final path = str('file_path');
      final oldText = str('old_string');
      final newText = str('new_string');
      if (path == null || path.trim().isEmpty) return null;
      if (oldText == null || newText == null) return null;
      return ToolDiff(path: path, oldText: oldText, newText: newText);
    case 'write':
      final path = str('file_path');
      final content = str('content');
      if (path == null || path.trim().isEmpty || content == null) return null;
      return ToolDiff(path: path, oldText: '', newText: content);
    case 'str_replace_editor':
      final path = str('path');
      if (path == null || path.trim().isEmpty) return null;
      switch (str('command')) {
        case 'create':
          final fileText = str('file_text') ?? '';
          return ToolDiff(path: path, oldText: '', newText: fileText);
        case 'str_replace':
          final oldStr = str('old_str');
          final newStr = str('new_str');
          if (oldStr == null || newStr == null) return null;
          return ToolDiff(path: path, oldText: oldStr, newText: newStr);
        default:
          return null;
      }
    default:
      return null;
  }
}

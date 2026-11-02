/// The phone used to show `edit` tool calls as one long argument blob; the web
/// renders just the changed lines. These tests pin the derivation that makes
/// the two agree.
library;

import 'dart:convert';

import 'package:dsh_mobile/src/tool_diff.dart';
import 'package:flutter_test/flutter_test.dart';

String args(Map<String, dynamic> value) => jsonEncode(value);

void main() {
  test('edit derives the replaced block, not the whole file', () {
    final diff = parseToolDiff(
      'edit',
      args({
        'file_path': '/repo/lib/main.dart',
        'old_string': 'final a = 1;\nfinal b = 2;',
        'new_string': 'final a = 1;\nfinal b = 3;\nfinal c = 4;',
        'replace_all': false,
      }),
    );

    expect(diff, isNotNull);
    expect(diff!.path, '/repo/lib/main.dart');
    expect(diff.isCreate, isFalse);
    expect(diff.removedLines, ['final a = 1;', 'final b = 2;']);
    expect(diff.addedLines, ['final a = 1;', 'final b = 3;', 'final c = 4;']);
    expect(
      diff.lines.map((l) => l.kind),
      everyElement(isA<ToolDiffKind>()),
    );
    expect(diff.lines.length, 5);
  });

  test('write is a whole-file addition', () {
    final diff = parseToolDiff(
      'write',
      args({'file_path': '/repo/NOTES.md', 'content': 'line one\nline two\n'}),
    );

    expect(diff, isNotNull);
    expect(diff!.isCreate, isTrue);
    expect(diff.removedLines, isEmpty);
    expect(diff.addedLines, ['line one', 'line two']);
  });

  test('str_replace_editor create and replace behave like write and edit', () {
    final create = parseToolDiff(
      'str_replace_editor',
      args({
        'command': 'create',
        'path': '/repo/a.txt',
        'file_text': 'hello',
      }),
    );
    expect(create?.isCreate, isTrue);
    expect(create?.addedLines, ['hello']);

    final replace = parseToolDiff(
      'str_replace_editor',
      args({
        'command': 'str_replace',
        'path': '/repo/a.txt',
        'old_str': 'hello',
        'new_str': 'hello world',
      }),
    );
    expect(replace?.isCreate, isFalse);
    expect(replace?.removedLines, ['hello']);
    expect(replace?.addedLines, ['hello world']);
  });

  test('other tools and malformed arguments fall back to the raw view', () {
    expect(parseToolDiff('bash', args({'command': 'ls'})), isNull);
    expect(parseToolDiff('edit', 'not json'), isNull);
    expect(parseToolDiff('edit', args({'file_path': '/repo/a'})), isNull);
    expect(parseToolDiff('', '{}'), isNull);
    expect(parseToolDiff('edit', ''), isNull);
  });

  test('a trailing newline does not add an empty diff line', () {
    expect(ToolDiff.splitLines('a\nb\n'), ['a', 'b']);
    expect(ToolDiff.splitLines(''), isEmpty);
    expect(ToolDiff.splitLines('\n'), ['']);
  });
}

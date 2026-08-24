import 'package:dsh_mobile/src/session_event_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts text and valid image attachments', () {
    final content = [
      {'type': 'text', 'text': '第一行'},
      {
        'type': 'image',
        'attachment': {
          'attachmentId': 'a1',
          'mediaType': 'image/png',
          'bytes': 12,
        },
      },
      {
        'type': 'image',
        'attachment': {'mediaType': 'image/png'},
      },
    ];

    expect(textFromContent(content), '第一行');
    final images = imageAttachmentsFromContent(content);
    expect(images, hasLength(1));
    expect(images.single.attachmentId, 'a1');
    expect(images.single.bytes, 12);
  });

  test('parses assistant blocks and ignores unsupported blocks', () {
    final parsed = parseAssistantContent([
      {'type': 'reasoning', 'text': '思考'},
      {'type': 'text', 'text': '答案'},
      {'type': 'tool-call', 'name': 'ignored'},
    ]);

    expect(parsed.blocks.map((block) => block.type), ['reasoning', 'text']);
    expect(parsed.blocks.map((block) => block.text), ['思考', '答案']);
    expect(parsed.images, isEmpty);
  });

  test('parses tool result text, images, and errors', () {
    final parsed = parseToolResult([
      {'type': 'text', 'text': '结果'},
      {
        'type': 'image',
        'attachment': {'attachmentId': 'a2', 'mediaType': 'image/jpeg'},
      },
      {'type': 'text', 'text': '失败', 'isError': true},
    ]);

    expect(parsed.text, '结果\n[图片]\n失败');
    expect(parsed.images.single.attachmentId, 'a2');
    expect(parsed.isError, isTrue);
  });

  test('filters hidden queue placements', () {
    final tasks = parseQueuedTasks([
      {
        'id': 'q1',
        'placement': 'queued',
        'message': {
          'content': [
            {'type': 'text', 'text': '处理'},
            {'type': 'image', 'data': 'x'},
          ],
        },
      },
      {
        'id': 'q2',
        'placement': 'context',
        'message': {
          'content': [
            {'type': 'text', 'text': '隐藏'},
          ],
        },
      },
    ]);

    expect(tasks, hasLength(1));
    expect(tasks.single.text, '处理');
    expect(tasks.single.imageCount, 1);
  });
}

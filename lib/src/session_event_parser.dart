/// Pure parsers for session event payloads.
library;

import 'queue.dart';

class ParsedAttachment {
  const ParsedAttachment({
    required this.attachmentId,
    required this.mediaType,
    this.bytes,
    this.width,
    this.height,
    this.name,
  });

  final String attachmentId;
  final String mediaType;
  final int? bytes;
  final int? width;
  final int? height;
  final String? name;
}

class ParsedAssistantContent {
  const ParsedAssistantContent({required this.blocks, required this.images});

  final List<({String type, String text})> blocks;
  final List<ParsedAttachment> images;
}

class ParsedToolResult {
  const ParsedToolResult({
    required this.text,
    required this.images,
    required this.isError,
  });

  final String text;
  final List<ParsedAttachment> images;
  final bool isError;
}

String textFromContent(Object? rawContent) {
  return (rawContent as List? ?? const [])
      .whereType<Map>()
      .where((block) => block['type'] == 'text')
      .map((block) => block['text'] as String? ?? '')
      .join('\n');
}

ParsedAttachment? parseAttachment(Object? raw) {
  if (raw is! Map ||
      raw['attachmentId'] is! String ||
      raw['mediaType'] is! String) {
    return null;
  }
  return ParsedAttachment(
    attachmentId: raw['attachmentId'] as String,
    mediaType: raw['mediaType'] as String,
    bytes: (raw['bytes'] as num?)?.toInt(),
    width: (raw['width'] as num?)?.toInt(),
    height: (raw['height'] as num?)?.toInt(),
    name: raw['name'] as String?,
  );
}

List<ParsedAttachment> imageAttachmentsFromContent(Object? rawContent) {
  return (rawContent as List? ?? const [])
      .whereType<Map>()
      .where((block) => block['type'] == 'image')
      .map((block) => parseAttachment(block['attachment']))
      .whereType<ParsedAttachment>()
      .toList();
}

ParsedAssistantContent parseAssistantContent(Object? rawContent) {
  final blocks = <({String type, String text})>[];
  final images = <ParsedAttachment>[];
  for (final block in (rawContent as List? ?? const []).whereType<Map>()) {
    switch (block['type']) {
      case 'text':
      case 'reasoning':
        blocks.add((
          type: block['type'] as String,
          text: block['text'] as String? ?? '',
        ));
      case 'image':
        final image = parseAttachment(block['attachment']);
        if (image != null) images.add(image);
    }
  }
  return ParsedAssistantContent(blocks: blocks, images: images);
}

ParsedToolResult parseToolResult(
  Object? rawContent, {
  bool eventError = false,
}) {
  final parts = <String>[];
  final images = <ParsedAttachment>[];
  var isError = eventError;
  for (final block in (rawContent as List? ?? const []).whereType<Map>()) {
    if (block['type'] == 'text') parts.add(block['text'] as String? ?? '');
    if (block['type'] == 'image') {
      parts.add('[图片]');
      final image = parseAttachment(block['attachment']);
      if (image != null) images.add(image);
    }
    if (block['isError'] == true) isError = true;
  }
  return ParsedToolResult(
    text: parts.join('\n'),
    images: images,
    isError: isError,
  );
}

List<QueuedTask> parseQueuedTasks(Object? rawItems) {
  return [
    for (final raw in (rawItems as List? ?? const []).whereType<Map>())
      if (raw['placement'] == 'queued' || raw['placement'] == 'steering')
        QueuedTask(
          id: raw['id'] as String? ?? '',
          placement: raw['placement'] as String,
          text: textFromContent((raw['message'] as Map?)?['content']),
          imageCount:
              ((raw['message'] as Map?)?['content'] as List? ?? const [])
                  .whereType<Map>()
                  .where((block) => block['type'] == 'image')
                  .length,
        ),
  ];
}

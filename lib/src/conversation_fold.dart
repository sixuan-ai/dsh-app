/// State-independent folding for core conversation events.
library;

import 'conversation.dart';
import 'session_event_parser.dart';

enum ConversationFoldResult { unhandled, handled, stop }

ConversationFoldResult foldCoreConversationEvent({
  required String type,
  required Map<String, dynamic> data,
  required int seq,
  required List<ChatItem> target,
  required bool live,
  required int? eventTime,
  required Map<String, ChatItem> streams,
  required Map<String, ChatItem> toolItems,
  required Map<String, ChatItem> pendingPrompts,
}) {
  switch (type) {
    case 'user/message':
      final source =
          (data['source'] as Map?)?.cast<String, dynamic>() ?? const {};
      final kind = source['kind'];
      final content = data['content'];
      final text = textFromContent(content);
      final images = imageAttachmentsFromContent(
        content,
      ).map(_chatImageFromParsed).toList();
      if (kind == 'user') {
        final rpcId = source['rpcId'] as String?;
        final provisional = rpcId != null && live
            ? pendingPrompts.remove(rpcId)
            : null;
        if (provisional != null) {
          provisional
            ..text = text
            ..images = images
            ..provisional = false
            ..time ??= eventTime;
          return ConversationFoldResult.stop;
        }
        target.add(ChatItem.user(id: 'u-$seq', text: text, images: images));
      }
      return ConversationFoldResult.handled;
    case 'assistant/message':
      final key = '${data['turn']}:${data['step']}';
      final streaming = live ? streams.remove(key) : null;
      if (streaming != null) target.remove(streaming);
      final parsed = parseAssistantContent(
        (data['message'] as Map?)?['content'],
      );
      final blocks = [
        for (final block in parsed.blocks)
          AssistantBlock(block.type, block.text),
      ];
      final images = parsed.images.map(_chatImageFromParsed).toList();
      if (blocks.isNotEmpty ||
          images.isNotEmpty ||
          data['interrupted'] == true) {
        target.add(
          ChatItem.assistant(
            id: 'a-$seq',
            blocks: blocks,
            images: images,
            usage: (data['usage'] as Map?)?.cast<String, dynamic>(),
            interrupted: data['interrupted'] == true,
          ),
        );
      }
      return ConversationFoldResult.handled;
    case 'assistant/chunk':
      if (!live) return ConversationFoldResult.stop;
      final turn = data['turn'];
      final step = data['step'];
      final chunk = (data['chunk'] as Map).cast<String, dynamic>();
      final key = '$turn:$step';
      final item = streams.putIfAbsent(key, () {
        final created = ChatItem.assistant(id: 'stream-$key', blocks: []);
        target.add(created);
        return created;
      });
      switch (chunk['type']) {
        case 'text-delta':
          appendAssistantDelta(
            item,
            'text',
            chunk['index'] as int? ?? 0,
            chunk['text'] as String? ?? '',
          );
        case 'reasoning-delta':
          appendAssistantDelta(
            item,
            'reasoning',
            chunk['index'] as int? ?? 0,
            chunk['text'] as String? ?? '',
          );
      }
      return ConversationFoldResult.handled;
    case 'tool/call':
      final item = ChatItem.tool(
        id: 't-$seq',
        callId: data['callId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        arguments: data['arguments'] as String? ?? '',
      );
      target.add(item);
      toolItems[item.callId] = item;
      return ConversationFoldResult.handled;
    case 'tool/result':
      final content =
          (data['message'] as Map?)?['content'] as List? ?? const [];
      if (content.isEmpty) return ConversationFoldResult.handled;
      final block = (content.first as Map).cast<String, dynamic>();
      final callId = block['toolCallId'] as String? ?? '';
      final item = toolItems[callId];
      final parsed = parseToolResult(
        block['content'],
        eventError: block['isError'] == true || data['error'] != null,
      );
      final images = parsed.images.map(_chatImageFromParsed).toList();
      if (item != null) {
        item
          ..resultText = parsed.text
          ..images = images
          ..resultIsError = parsed.isError
          ..completed = true;
      } else if (live) {
        target.add(
          ChatItem.tool(
              id: 'tr-$seq',
              callId: callId,
              name: 'tool',
              arguments: '',
            )
            ..resultText = parsed.text
            ..images = images
            ..resultIsError = parsed.isError
            ..completed = true,
        );
      }
      return ConversationFoldResult.handled;
    default:
      return ConversationFoldResult.unhandled;
  }
}

void appendAssistantDelta(ChatItem item, String type, int index, String delta) {
  while (item.blocks.length <= index) {
    item.blocks.add(AssistantBlock(type, ''));
  }
  final block = item.blocks[index];
  if (block.type != type) {
    item.blocks.insert(index, AssistantBlock(type, delta));
    return;
  }
  block.text += delta;
}

ChatImage _chatImageFromParsed(ParsedAttachment image) => ChatImage(
  attachmentId: image.attachmentId,
  mediaType: image.mediaType,
  bytes: image.bytes,
  width: image.width,
  height: image.height,
  name: image.name,
);

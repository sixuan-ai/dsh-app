/// State-independent folding for core conversation events.
library;

import 'conversation.dart';
import 'session_event_parser.dart';

enum ConversationFoldResult { unhandled, handled, stop }

class LocalCommandRows {
  const LocalCommandRows({
    required this.line,
    required this.echo,
    required this.status,
  });

  final String line;
  final ChatItem echo;
  final ChatItem status;
}

typedef TakeLocalCommand = LocalCommandRows? Function(String name);
typedef ReplaceConversationItem =
    void Function(ChatItem oldItem, ChatItem replacement);
typedef TurnErrorHandler = void Function(String rawMessage, int seq);

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
  TakeLocalCommand? takeLocalCommand,
  ReplaceConversationItem? replaceItem,
  TurnErrorHandler? onTurnError,
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
    case 'turn/end':
      if (live) {
        final turn = data['turn'];
        final prefix = turn == null ? null : '$turn:';
        final streamKeys = streams.keys
            .where((key) => prefix == null || key.startsWith(prefix))
            .toList();
        for (final key in streamKeys) {
          final stream = streams.remove(key);
          if (stream != null) target.remove(stream);
        }
        final reason = (data['reason'] as Map?)?.cast<String, dynamic>();
        if (reason?['kind'] == 'error') {
          final failure = (reason?['error'] as Map?)?.cast<String, dynamic>();
          onTurnError?.call(failure?['message'] as String? ?? '未知错误', seq);
        }
      }
      return ConversationFoldResult.handled;
    case 'command/run':
      final commandId = data['commandId'] as String? ?? '';
      final name = data['name'] as String? ?? '';
      if (commandId.isEmpty || name.isEmpty) return ConversationFoldResult.stop;
      if (target.any((item) => item.id == 'cmdrun-$commandId')) {
        return ConversationFoldResult.stop;
      }
      final args = data['args'] as String?;
      final line = '/$name${args ?? ''}'.trimRight();
      final local = live ? takeLocalCommand?.call(name) : null;
      final shown = local?.line ?? line;
      final echo = ChatItem.user(id: 'cmdin-$commandId', text: shown);
      final status = ChatItem.notice(
        id: 'cmdrun-$commandId',
        text: '正在执行 $shown …',
      )..pending = true;
      if (local != null && replaceItem != null) {
        replaceItem(local.echo, echo);
        replaceItem(local.status, status);
      } else {
        target
          ..add(echo)
          ..add(status);
      }
      return ConversationFoldResult.handled;
    case 'command/done':
      final commandId = data['commandId'] as String? ?? '';
      final text = data['text'] as String? ?? '';
      final isError = data['kind'] == 'error';
      ChatItem? status;
      for (final candidate in target) {
        if (candidate.id == 'cmdrun-$commandId') {
          status = candidate;
          break;
        }
      }
      if (status != null) {
        status
          ..text = text.isNotEmpty ? text : (isError ? '命令执行失败' : '执行完成')
          ..isError = isError
          ..pending = false;
      } else if (text.isNotEmpty) {
        target.add(
          ChatItem.notice(
            id: 'cmddone-$commandId',
            text: text,
            isError: isError,
          ),
        );
      }
      return ConversationFoldResult.handled;
    case 'todo/write':
      if (!live) return ConversationFoldResult.stop;
      final todos = (data['todos'] as List?) ?? const [];
      if (todos.isNotEmpty) {
        final lines = todos
            .whereType<Map>()
            .map((todo) {
              final mark = switch (todo['status']) {
                'completed' => '☑',
                'in_progress' => '◐',
                _ => '☐',
              };
              return '$mark ${todo['content']}';
            })
            .join('\n');
        target.add(ChatItem.notice(id: 'todo-$seq', text: lines));
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

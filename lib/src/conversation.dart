/// Renderable conversation models shared by state, persistence, and widgets.
library;

/// An image reference in a durable user or assistant message.
class ChatImage {
  ChatImage({
    required this.attachmentId,
    required this.mediaType,
    this.bytes,
    this.width,
    this.height,
    this.name,
    this.data,
  });

  final String attachmentId;
  final String mediaType;
  final int? bytes;
  final int? width;
  final int? height;
  final String? name;
  String? data;
}

/// Renderable conversation unit produced by the event fold.
class ChatItem {
  ChatItem.user({
    required this.id,
    required this.text,
    this.provisional = false,
    this.images = const [],
  }) : kind = ChatItemKind.user,
       time = null;

  ChatItem.assistant({
    required this.id,
    required this.blocks,
    this.images = const [],
    this.usage,
    this.interrupted = false,
  }) : kind = ChatItemKind.assistant,
       time = null;

  ChatItem.tool({
    required this.id,
    required this.callId,
    required this.name,
    required this.arguments,
  }) : kind = ChatItemKind.tool,
       time = null;

  ChatItem.notice({
    required this.id,
    required this.text,
    this.isError = false,
    this.retryText,
  }) : kind = ChatItemKind.notice,
       time = null;

  final ChatItemKind kind;
  final String id;
  int? time;
  String text = '';
  bool provisional = false;
  List<ChatImage> images = [];
  List<AssistantBlock> blocks = [];
  Map<String, dynamic>? usage;
  bool interrupted = false;
  bool isError = false;
  String? retryText;
  bool pending = false;
  String callId = '';
  String name = '';
  String arguments = '';
  String? resultText;
  bool resultIsError = false;
  bool completed = false;
}

enum ChatItemKind { user, assistant, tool, notice }

class AssistantBlock {
  AssistantBlock(this.type, this.text);

  final String type;
  String text;
}

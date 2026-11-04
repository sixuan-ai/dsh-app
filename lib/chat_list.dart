/// Conversation list scrolling, history loading, and time dividers.
library;

import 'package:flutter/material.dart';

import 'chat_view.dart';
import 'src/theme.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Chat list and items
// ---------------------------------------------------------------------------

class ChatList extends StatefulWidget {
  const ChatList({super.key, required this.state});

  final AppState state;

  @override
  State<ChatList> createState() => _ChatListState();
}

int chatItemRevision(ChatItem item) => Object.hashAll([
  item.id,
  item.kind,
  item.time,
  item.text,
  item.provisional,
  item.interrupted,
  item.isError,
  item.retryText,
  item.pending,
  item.callId,
  item.name,
  item.arguments,
  item.resultText,
  item.resultIsError,
  item.completed,
  for (final block in item.blocks) Object.hash(block.type, block.text),
  for (final image in item.images)
    Object.hash(
      image.attachmentId,
      image.mediaType,
      image.bytes,
      image.width,
      image.height,
      image.name,
      image.data?.length,
    ),
]);

int? chatTailRevision(List<ChatItem> items) =>
    items.isEmpty ? null : chatItemRevision(items.last);

class ChatItemBoundary extends StatefulWidget {
  const ChatItemBoundary({
    super.key,
    required this.state,
    required this.item,
    required this.animate,
  });

  final AppState state;
  final ChatItem item;
  final bool animate;

  @override
  State<ChatItemBoundary> createState() => _ChatItemBoundaryState();
}

class _ChatItemBoundaryState extends State<ChatItemBoundary> {
  int? _revision;
  late Widget _child;

  @override
  Widget build(BuildContext context) {
    final revision = chatItemRevision(widget.item);
    if (_revision != revision) {
      _revision = revision;
      _child = ChatItemView(
        key: ValueKey('${widget.item.id}:$revision'),
        state: widget.state,
        item: widget.item,
        animate: widget.animate,
      );
    }
    return _child;
  }
}

class _ChatListState extends State<ChatList> {
  final ScrollController _controller = ScrollController();
  int _lastCount = -1;
  int? _lastTailRevision;
  bool _scrollScheduled = false;

  /// Entrance-animation baseline: items at or above this index animate in.
  /// Initialized to the full list so history loads never animate.
  int _animBaseline = 0;
  String? _animSession;

  /// New content arrived while the user was reading above the fold.
  bool _hasNewBelow = false;
  bool _wasNearBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _nearBottom {
    if (!_controller.hasClients) return true;
    final position = _controller.position;
    return position.maxScrollExtent - position.pixels < 240;
  }

  void _onScroll() {
    final near = _nearBottom;
    if (near == _wasNearBottom) return;
    _wasNearBottom = near;
    if (near) _hasNewBelow = false;
    setState(() {});
  }

  void _maybeScroll() {
    final items = widget.state.items;
    final count = items.length;
    final countChanged = count != _lastCount;
    final tailRevision = chatTailRevision(items);
    final tailChanged = tailRevision != _lastTailRevision;
    if (countChanged || tailChanged) {
      if (_nearBottom) {
        _scheduleScrollToBottom();
      } else if (countChanged && count > _lastCount) {
        // Appended while reading history: keep position, flag the jump button.
        _hasNewBelow = true;
      }
    }
    _lastCount = count;
    _lastTailRevision = tailRevision;
  }

  void _scheduleScrollToBottom() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _hasNewBelow = false;
    _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    _maybeScroll();
    if (state.selectedSessionId != _animSession) {
      _animSession = state.selectedSessionId;
      _animBaseline = state.items.length;
    }
    if (state.items.isEmpty) {
      if (state.loadingHistory) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: P.accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 24,
                color: P.accentLight,
              ),
            ),
            SizedBox(height: 12),
            Text('发送消息开始对话', style: TextStyle(color: P.textTertiary)),
          ],
        ),
      );
    }
    final animateFrom = _animBaseline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animBaseline = state.items.length;
    });
    final extra = state.hasMoreHistory ? 1 : 0;
    final listView = ListView.builder(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.items.length + extra,
      itemBuilder: (context, index) {
        if (index < extra) {
          return Center(
            child: TextButton.icon(
              onPressed: state.loadingHistory
                  ? null
                  : () => state.loadHistory(
                      state.selectedSessionId!,
                      older: true,
                    ),
              icon: state.loadingHistory
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: const Text('加载更早的消息'),
            ),
          );
        }
        final itemIndex = index - extra;
        final item = state.items[itemIndex];
        final prev = itemIndex > 0 ? state.items[itemIndex - 1] : null;
        final showTime = _needsTimeDivider(prev, item);
        final body = ChatItemBoundary(
          key: ValueKey(item.id),
          state: state,
          item: item,
          animate: itemIndex >= animateFrom,
        );
        if (!showTime) return body;
        return Column(
          children: [
            _TimeDivider(time: item.time!),
            body,
          ],
        );
      },
    );
    return Stack(
      children: [
        Scrollbar(
          controller: _controller,
          interactive: true,
          thickness: 3,
          radius: const Radius.circular(2),
          child: state.hasMoreHistory
              ? RefreshIndicator(
                  color: P.accent,
                  backgroundColor: P.cardAlt,
                  onRefresh: () =>
                      state.loadHistory(state.selectedSessionId!, older: true),
                  child: listView,
                )
              : listView,
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: _ScrollToBottomButton(
            visible: !_wasNearBottom,
            hasNew: _hasNewBelow,
            onTap: _scrollToBottom,
          ),
        ),
      ],
    );
  }
}

/// QQ-style rule: a divider appears above an item when it is the first
/// timestamped item or follows a gap of more than five minutes.
bool _needsTimeDivider(ChatItem? prev, ChatItem current) {
  final time = current.time;
  if (time == null) return false;
  final prevTime = prev?.time;
  if (prevTime == null) return true;
  return time - prevTime > 5 * 60 * 1000;
}

String _fmtDividerTime(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays <= 0) return hm;
  if (diffDays == 1) return '昨天 $hm';
  if (t.year == now.year) return '${t.month}月${t.day}日 $hm';
  return '${t.year}年${t.month}月${t.day}日 $hm';
}

/// Small centered timestamp row between messages.
class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.time});

  final int time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: P.fillSubtle,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _fmtDividerTime(time),
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.2,
              color: P.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating jump-to-latest button with a new-content accent dot.
class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({
    required this.visible,
    required this.hasNew,
    required this.onTap,
  });

  final bool visible;
  final bool hasNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: P.cardAlt,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: P.neuShadow.withValues(alpha: 0.3),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: P.accentLight,
                  ),
                ),
              ),
            ),
            if (hasNew)
              Positioned(
                top: -1,
                right: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: P.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: P.cardAlt, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

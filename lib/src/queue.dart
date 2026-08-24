/// Queue data and wire helpers for server-authoritative session inbox items.
library;

import 'package:flutter/foundation.dart';

/// One server-authoritative pending task in a session inbox.
@immutable
class QueuedTask {
  const QueuedTask({
    required this.id,
    required this.placement,
    required this.text,
    required this.imageCount,
  });

  final String id;
  final String placement;
  final String text;
  final int imageCount;
}

Map<String, dynamic> queueEditAction(String text) => {
  'kind': 'edit',
  'content': [
    {'type': 'text', 'text': text},
  ],
};

Map<String, dynamic> queueRemoveAction() => {'kind': 'remove'};

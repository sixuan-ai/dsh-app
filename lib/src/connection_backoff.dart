/// Reconnect backoff calculation shared by the connection lifecycle.
library;

import 'dart:math' as math;

const reconnectBaseDelayMs = 2000;
const reconnectMaxDelayMs = 30000;
const reconnectJitterRatio = 0.25;

int reconnectBaseDelayForAttempt(int attempt) {
  final safeAttempt = math.max(0, attempt);
  return math
      .min(reconnectBaseDelayMs * math.pow(2, safeAttempt), reconnectMaxDelayMs)
      .round();
}

Duration reconnectDelayForAttempt(int attempt, {required double jitterUnit}) {
  final base = reconnectBaseDelayForAttempt(attempt);
  final unit = jitterUnit.clamp(-1.0, 1.0);
  final jitter = base * reconnectJitterRatio * unit;
  return Duration(milliseconds: (base + jitter).round());
}

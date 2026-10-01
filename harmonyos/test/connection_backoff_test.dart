import 'package:dsh_mobile/src/connection_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('doubles reconnect delay until the cap', () {
    expect(reconnectBaseDelayForAttempt(0), 2000);
    expect(reconnectBaseDelayForAttempt(1), 4000);
    expect(reconnectBaseDelayForAttempt(2), 8000);
    expect(reconnectBaseDelayForAttempt(3), 16000);
    expect(reconnectBaseDelayForAttempt(4), 30000);
    expect(reconnectBaseDelayForAttempt(20), 30000);
  });

  test('negative attempts use the initial delay', () {
    expect(reconnectBaseDelayForAttempt(-5), 2000);
  });

  test('jitter stays within plus or minus twenty five percent', () {
    expect(
      reconnectDelayForAttempt(0, jitterUnit: -1),
      const Duration(milliseconds: 1500),
    );
    expect(
      reconnectDelayForAttempt(0, jitterUnit: 0),
      const Duration(milliseconds: 2000),
    );
    expect(
      reconnectDelayForAttempt(0, jitterUnit: 1),
      const Duration(milliseconds: 2500),
    );
  });

  test('out of range jitter input is clamped', () {
    expect(
      reconnectDelayForAttempt(1, jitterUnit: 9),
      const Duration(milliseconds: 5000),
    );
    expect(
      reconnectDelayForAttempt(1, jitterUnit: -9),
      const Duration(milliseconds: 3000),
    );
  });
}

import 'package:dsh_mobile/src/ping_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregates min, avg, max, jitter, and success rate', () {
    final stats = PingStats.fromSamples([40, 60, 80], 1);
    expect(stats.min, 40);
    expect(stats.max, 80);
    expect(stats.avg, 60);
    expect(stats.jitter, closeTo(13.33, 0.01));
    expect(stats.total, 4);
    expect(stats.successRate, closeTo(0.75, 0.001));
  });

  test('empty run reports zero stats and worst rating', () {
    final stats = PingStats.fromSamples(const [], 2);
    expect(stats.avg, 0);
    expect(stats.total, 2);
    expect(stats.rating.label, '不稳定');
  });

  test('rating buckets follow latency thresholds', () {
    expect(PingStats.fromSamples([30], 0).rating.label, '极好');
    expect(PingStats.fromSamples([100], 0).rating.label, '良好');
    expect(PingStats.fromSamples([250], 0).rating.label, '一般');
    expect(PingStats.fromSamples([600], 0).rating.label, '较差');
  });
}

/// Latency statistics for a series of host ping samples.
library;

/// Aggregated round-trip stats for one diagnostics run.
class PingStats {
  const PingStats({
    required this.samples,
    required this.failures,
    required this.min,
    required this.avg,
    required this.max,
    required this.jitter,
  });

  /// Computes stats from successful RTT samples (ms) and a failure count.
  factory PingStats.fromSamples(List<int> samples, int failures) {
    if (samples.isEmpty) {
      return PingStats(
        samples: samples,
        failures: failures,
        min: 0,
        avg: 0,
        max: 0,
        jitter: 0,
      );
    }
    var min = samples.first;
    var max = samples.first;
    var sum = 0;
    for (final sample in samples) {
      if (sample < min) min = sample;
      if (sample > max) max = sample;
      sum += sample;
    }
    final avg = sum / samples.length;
    // Mean absolute deviation is a stable, easy-to-read jitter figure.
    var deviation = 0.0;
    for (final sample in samples) {
      deviation += (sample - avg).abs();
    }
    return PingStats(
      samples: samples,
      failures: failures,
      min: min,
      avg: avg,
      max: max,
      jitter: deviation / samples.length,
    );
  }

  /// Successful round-trip samples in milliseconds, in send order.
  final List<int> samples;

  /// Samples that failed outright (timeout or transport error).
  final int failures;

  final int min;
  final double avg;
  final int max;

  /// Mean absolute deviation of the samples, in milliseconds.
  final double jitter;

  int get total => samples.length + failures;

  double get successRate => total == 0 ? 0 : samples.length / total;

  /// Coarse link-quality rating from average latency and loss.
  ({String label, int level}) get rating {
    if (successRate < 1) return (label: '不稳定', level: 2);
    if (avg < 60) return (label: '极好', level: 0);
    if (avg < 150) return (label: '良好', level: 1);
    if (avg < 400) return (label: '一般', level: 2);
    return (label: '较差', level: 3);
  }
}

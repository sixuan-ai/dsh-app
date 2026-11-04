/// Network diagnostics page: RTT sampling against the connected host.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'src/ping_stats.dart';
import 'src/theme.dart';
import 'state.dart';

/// Measures round-trip latency to the connected DSH host with repeated
/// `host.describe` calls and presents min/avg/max/jitter plus loss.
class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key, required this.state});

  final AppState state;

  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  static const _sampleCount = 8;

  final List<int> _samples = [];
  int _failures = 0;
  bool _running = false;
  bool _ranOnce = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _ranOnce = true;
      _samples.clear();
      _failures = 0;
    });
    for (var i = 0; i < _sampleCount; i++) {
      try {
        final ms = await widget.state.pingHost().timeout(Duration(seconds: 5));
        if (!mounted) return;
        setState(() => _samples.add(ms));
      } catch (_) {
        if (!mounted) return;
        setState(() => _failures++);
      }
      if (i + 1 < _sampleCount) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted) return;
    }
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = PingStats.fromSamples(_samples, _failures);
    final rating = stats.rating;
    final ratingColor = switch (rating.level) {
      0 => P.success,
      1 => P.accentLight,
      2 => P.warning,
      _ => P.danger,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('网络诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: P.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: P.fillLight),
              boxShadow: P.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined, size: 18, color: P.accentLight),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.state.serverUrl.isEmpty
                            ? '未连接服务器'
                            : Uri.parse(widget.state.serverUrl).host,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  '对服务器发送 $_sampleCount 次探测，统计往返延迟与成功率。',
                  style: TextStyle(fontSize: 12, color: P.textTertiary),
                ),
              ],
            ),
          ),
          SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: P.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: P.fillLight),
              boxShadow: P.cardShadow,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_running)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: P.accentLight,
                          ),
                        ),
                      ),
                    Text(
                      _samples.isEmpty && _failures == 0
                          ? (_running ? '正在探测…' : '尚未开始')
                          : '${stats.avg.toStringAsFixed(0)} ms',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: ratingColor,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  _samples.isEmpty && _failures == 0
                      ? '平均延迟'
                      : '平均延迟 · ${rating.label}',
                  style: TextStyle(fontSize: 12.5, color: ratingColor),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    _stat('最小', '${stats.min} ms'),
                    _stat('最大', '${stats.max} ms'),
                    _stat('抖动', '${stats.jitter.toStringAsFixed(0)} ms'),
                    _stat(
                      '成功率',
                      stats.total == 0
                          ? '—'
                          : '${(stats.successRate * 100).toStringAsFixed(0)}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 14),
          if (_samples.isNotEmpty || _failures > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                color: P.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: P.fillLight),
                boxShadow: P.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '逐次探测',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: P.textSecondary,
                    ),
                  ),
                  SizedBox(height: 10),
                  for (var i = 0; i < _samples.length; i++)
                    _sampleBar(i + 1, _samples[i], stats.max),
                  if (_failures > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        '$_failures 次探测失败（超时或连接错误）',
                        style: TextStyle(fontSize: 11.5, color: P.danger),
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_ranOnce && !_running ? '重新检测' : '正在检测…'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: P.textTertiary)),
        ],
      ),
    );
  }

  Widget _sampleBar(int index, int ms, int max) {
    final ratio = max <= 0 ? 0.0 : ms / max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$index',
              style: TextStyle(fontSize: 11, color: P.textTertiary),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: P.fillLight,
                valueColor: AlwaysStoppedAnimation(P.accentLight),
              ),
            ),
          ),
          SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Text(
              '$ms ms',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: P.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

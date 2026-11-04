/// Session usage and context statistics widgets.
library;

import 'package:flutter/material.dart';

import 'src/theme.dart';
import 'state.dart';

class StatsBar extends StatelessWidget {
  const StatsBar({super.key, required this.state});

  final AppState state;

  num? _num(Map<String, dynamic>? map, String key) => map?[key] as num?;

  @override
  Widget build(BuildContext context) {
    final sessionId = state.selectedSessionId;
    if (sessionId == null) return const SizedBox.shrink();
    final stats = state.projectionOf(sessionId, 'sessionStats');
    final usage = state.projectionOf(sessionId, 'tokenUsage');
    final pressure = state.projectionOf(sessionId, 'contextPressure');
    if (stats == null && usage == null) return const SizedBox.shrink();

    final chips = <Widget>[];
    final turns = _num(stats, 'turns');
    final steps = _num(stats, 'steps');
    if (turns != null && steps != null) {
      chips.add(_StatChip(icon: Icons.loop, label: '$turns 轮 · $steps 步'));
    }
    final llmMs = _num(stats, 'llmMs');
    final toolMs = _num(stats, 'toolMs');
    if (llmMs != null) {
      chips.add(
        _StatChip(
          icon: Icons.schedule,
          label: 'LLM ${_fmtDuration(llmMs)} · 工具 ${_fmtDuration(toolMs ?? 0)}',
        ),
      );
    }
    final ttftMs = _num(stats, 'ttftMs');
    final ttftSteps = _num(stats, 'ttftSteps');
    if (ttftMs != null && ttftSteps != null && ttftSteps > 0) {
      chips.add(
        _StatChip(
          icon: Icons.bolt,
          label: '首 token 平均 ${_fmtDuration(ttftMs / ttftSteps)}',
        ),
      );
    }
    final decodeMs = _num(stats, 'decodeMs');
    final decodeTokens = _num(stats, 'decodeTokens');
    if (decodeMs != null && decodeMs > 0 && decodeTokens != null) {
      final speed = decodeTokens / (decodeMs / 1000);
      chips.add(
        _StatChip(
          icon: Icons.speed,
          label: '${speed.toStringAsFixed(0)} tok/s',
        ),
      );
    }
    final uncached = _num(usage, 'uncachedInputTokens');
    final output = _num(usage, 'outputTokens');
    final cacheRead = _num(usage, 'cacheReadTokens');
    if (cacheRead != null && uncached != null && cacheRead + uncached > 0) {
      final pct = cacheRead / (cacheRead + uncached) * 100;
      chips.add(
        _StatChip(icon: Icons.cached, label: '缓存命中 ${pct.toStringAsFixed(0)}%'),
      );
    }
    if (uncached != null || output != null) {
      chips.add(
        _StatChip(
          icon: Icons.swap_vert,
          label:
              '输入 ${_fmtTokens(uncached ?? 0)} · 输出 ${_fmtTokens(output ?? 0)}',
        ),
      );
    }
    final projected =
        _num(pressure, 'projectedTokens') ?? _num(pressure, 'pressureTokens');
    final window = _num(pressure, 'contextWindow');
    if (projected != null && window != null && window > 0) {
      chips.add(_ContextChip(used: projected, total: window));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: P.fillLight)),
      ),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => chips[index],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: P.fillSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: P.fillMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: P.accentLight),
          SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11.5, color: P.textSecondary)),
        ],
      ),
    );
  }
}

/// Context-window usage chip with inline progress bar.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.used, required this.total});

  final num used;
  final num total;

  @override
  Widget build(BuildContext context) {
    final ratio = (used / total).clamp(0.0, 1.0);
    final pct = ratio * 100;
    final color = pct >= 85
        ? P.danger
        : pct >= 70
        ? P.warning
        : P.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.data_usage, size: 13, color: color),
          SizedBox(width: 5),
          Text(
            '上下文 ${pct.toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11.5, color: color),
          ),
          SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 5,
                backgroundColor: P.fillLight,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDuration(num ms) {
  if (ms < 1000) return '${ms.round()}ms';
  final seconds = ms / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).round();
  return '${minutes}m${rest}s';
}

String _fmtTokens(num tokens) {
  if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M tok';
  if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K tok';
  return '$tokens tok';
}

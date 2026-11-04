/// Compact badge showing a session's collaboration mode (goal / plan / auto),
/// derived from the session projections by [AppState.sessionModeOf].
library;

import 'package:flutter/material.dart';

import 'src/l10n.dart';
import 'src/theme.dart';
import 'state.dart';

class SessionModeBadge extends StatelessWidget {
  const SessionModeBadge({super.key, required this.mode, this.compact = false});

  final SessionMode mode;

  /// Compact layout for dense rows (smaller text and padding).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (mode) {
      SessionMode.goal => (S.modeGoal, P.agent, Icons.flag_outlined),
      SessionMode.plan => (S.modePlan, P.agent, Icons.edit_note_outlined),
      SessionMode.auto => (S.modeAuto, P.agent, Icons.auto_awesome),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10 : 12, color: color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

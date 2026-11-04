/// Release notes page and post-update summary dialog.
library;

import 'package:flutter/material.dart';

import 'src/changelog.dart';
import 'src/theme.dart';

// ---------------------------------------------------------------------------
// Changelog
// ---------------------------------------------------------------------------

/// Display metadata of one changelog change type.
({Color color, IconData icon, String label}) _changeTypeMeta(
  ChangelogChangeType type,
) => switch (type) {
  ChangelogChangeType.feature => (
    color: P.success,
    icon: Icons.auto_awesome,
    label: '新功能',
  ),
  ChangelogChangeType.improvement => (
    color: P.accentLight,
    icon: Icons.trending_up,
    label: '优化',
  ),
  ChangelogChangeType.fix => (
    color: P.warning,
    icon: Icons.bug_report_outlined,
    label: '修复',
  ),
};

/// One change row: colored type chip plus the change text.
class _ChangelogChangeRow extends StatelessWidget {
  const _ChangelogChangeRow({required this.change});

  final ChangelogChange change;

  @override
  Widget build(BuildContext context) {
    final meta = _changeTypeMeta(change.type);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: meta.color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(meta.icon, size: 11, color: meta.color),
                SizedBox(width: 3),
                Text(
                  meta.label,
                  style: TextStyle(fontSize: 10, color: meta.color),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              change.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: P.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full release-notes page, reachable from the drawer.
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final release in kChangelog)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: P.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: release.version == kLatestRelease.version
                      ? P.accent.withValues(alpha: 0.35)
                      : P.fillLight,
                ),
                boxShadow: release.version == kLatestRelease.version
                    ? [
                        BoxShadow(
                          color: P.accent.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'v${release.version}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (release.version == kLatestRelease.version) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: P.brandGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '当前',
                            style: TextStyle(fontSize: 10, color: P.onAccent),
                          ),
                        ),
                      ],
                      Spacer(),
                      Text(
                        release.date,
                        style: TextStyle(fontSize: 12, color: P.textTertiary),
                      ),
                    ],
                  ),
                  Divider(height: 18),
                  for (final change in release.changes)
                    _ChangelogChangeRow(change: change),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Post-update dialog summarizing the latest release.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final release = kLatestRelease;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.new_releases_outlined, color: P.accentLight),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'v${release.version} 更新内容',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in release.changes)
                _ChangelogChangeRow(change: change),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => ChangelogPage()));
          },
          child: const Text('查看全部'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

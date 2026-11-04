/// Contact support hub: in-app channels only (feedback form, community,
/// setup guide, changelog). No external contact info is shown.
library;

import 'package:flutter/material.dart';

import 'feedback_page.dart';
import 'social_page.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'state.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({
    super.key,
    required this.state,
    required this.socialBaseUrl,
    required this.connectionGuideBuilder,
    required this.changelogBuilder,
  });

  final AppState state;
  final String socialBaseUrl;
  final WidgetBuilder connectionGuideBuilder;
  final WidgetBuilder changelogBuilder;

  void _openGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: connectionGuideBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.supportTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Text(
                S.supportIntro,
                style: TextStyle(color: P.textSecondary, fontSize: 13.5),
              ),
            ),
            _ChannelCard(
              icon: Icons.feedback_outlined,
              color: P.accent,
              title: S.feedback,
              subtitle: S.feedbackDesc,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FeedbackPage(
                    username: state.accountUsername,
                    password: state.accountPassword,
                  ),
                ),
              ),
            ),
            _ChannelCard(
              icon: Icons.forum_outlined,
              color: P.accent2,
              title: S.community,
              subtitle: S.communityDesc,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CommunityPage(state: state, socialBaseUrl: socialBaseUrl),
                ),
              ),
            ),
            _ChannelCard(
              icon: Icons.menu_book_outlined,
              color: P.warning,
              title: S.connectionGuide,
              subtitle: S.computerConfig,
              onTap: () => _openGuide(context),
            ),
            _ChannelCard(
              icon: Icons.new_releases_outlined,
              color: P.info,
              title: S.updateLog,
              subtitle: S.checkUpdate,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: changelogBuilder)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: P.fillSubtle,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: P.textTertiary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: P.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

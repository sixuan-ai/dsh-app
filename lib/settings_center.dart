/// Settings center: language, theme, connection, and help entries.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'balance_page.dart';
import 'dsh_update_page.dart';
import 'dev_tools_page.dart';
import 'feedback_page.dart';
import 'support_page.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'state.dart';
import 'app_account_page.dart';
import 'src/ui/glass.dart';
import 'src/ui/neumorphic.dart';

class SettingsCenterPage extends StatefulWidget {
  const SettingsCenterPage({
    super.key,
    required this.language,
    required this.theme,
    required this.state,
    required this.socialBaseUrl,
    required this.onConnectionCenter,
    required this.onCheckUpdate,
    required this.connectionGuideBuilder,
    required this.changelogBuilder,
  });

  final LanguageController language;
  final ThemeController theme;
  final AppState state;
  final String socialBaseUrl;
  final VoidCallback onConnectionCenter;
  final VoidCallback onCheckUpdate;
  final WidgetBuilder connectionGuideBuilder;
  final WidgetBuilder changelogBuilder;

  @override
  State<SettingsCenterPage> createState() => _SettingsCenterPageState();
}

class _SettingsCenterPageState extends State<SettingsCenterPage> {
  String? _version;

  /// Developer mode switch: off by default, persisted across launches.
  /// When on, the app debugging tools (host DSH status/logs/restart) become
  /// reachable below the switch.
  bool _devMode = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
    unawaited(_loadDevMode());
  }

  Future<void> _loadDevMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('devMode') ?? false;
      if (mounted && enabled != _devMode) {
        setState(() => _devMode = enabled);
      }
    } catch (_) {
      // Prefs unavailable: keep the in-memory default.
    }
  }

  Future<void> _setDevMode(bool value) async {
    setState(() => _devMode = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('devMode', value);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = 'v${info.version}+${info.buildNumber}');
    }
  }

  void _openGuide() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: widget.connectionGuideBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.settings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: GlassPanel(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: P.accent,
                      foregroundColor: P.onAccent,
                      child: Text(
                        widget.state.signedInAccount == null ? '访' : '思',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.state.signedInAccount?.email ?? S.guestMode,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            S.optionalAccountHint,
                            style: TextStyle(
                              color: P.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '思玄账号',
                      icon: const Icon(Icons.account_circle_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AppAccountPage(
                            state: widget.state,
                            initialMode: AppAccountMode.login,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _SectionHeader(S.language),
            AnimatedBuilder(
              animation: widget.language,
              builder: (context, _) =>
                  _LanguagePicker(controller: widget.language),
            ),
            _SectionHeader(S.theme),
            AnimatedBuilder(
              animation: widget.theme,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        MediaQuery.textScalerOf(context).scale(14) > 18 ? 1 : 2;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final spec in kAppThemes)
                          SizedBox(
                            width: width,
                            child: ThemeChoiceCard(
                              spec: spec,
                              selected: spec.id == widget.theme.themeId,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.theme.select(spec.id);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            _SectionHeader(S.connection),
            _EntryTile(
              icon: Icons.alt_route,
              title: S.connectionCenter,
              subtitle: S.localRemote,
              onTap: () {
                Navigator.of(context).pop();
                widget.onConnectionCenter();
              },
            ),
            _EntryTile(
              icon: Icons.account_balance_wallet_outlined,
              title: S.balanceTitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BalancePage(
                    username: widget.state.accountUsername,
                    password: widget.state.accountPassword,
                  ),
                ),
              ),
            ),
            _EntryTile(
              icon: Icons.terminal_outlined,
              title: S.dshUpdate,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DshUpdatePage(
                    username: widget.state.accountUsername,
                    password: widget.state.accountPassword,
                  ),
                ),
              ),
            ),
            _SectionHeader(S.developerSection),
            SwitchListTile(
              secondary: Icon(
                Icons.developer_mode_outlined,
                color: P.textSecondary,
              ),
              title: Text(S.developerMode),
              subtitle: Text(
                S.developerModeHint,
                style: TextStyle(color: P.textTertiary, fontSize: 12.5),
              ),
              value: _devMode,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                unawaited(_setDevMode(value));
              },
            ),
            if (_devMode)
              _EntryTile(
                icon: Icons.terminal_outlined,
                title: S.devTools,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DevToolsPage(
                      username: widget.state.accountUsername,
                      password: widget.state.accountPassword,
                    ),
                  ),
                ),
              ),
            _SectionHeader(S.help),
            _EntryTile(
              icon: Icons.feedback_outlined,
              title: S.feedback,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FeedbackPage(
                    username: widget.state.accountUsername,
                    password: widget.state.accountPassword,
                  ),
                ),
              ),
            ),
            _EntryTile(
              icon: Icons.headset_mic_outlined,
              title: S.support,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SupportPage(
                    state: widget.state,
                    socialBaseUrl: widget.socialBaseUrl,
                    connectionGuideBuilder: widget.connectionGuideBuilder,
                    changelogBuilder: widget.changelogBuilder,
                  ),
                ),
              ),
            ),
            _EntryTile(
              icon: Icons.menu_book_outlined,
              title: S.connectionGuide,
              subtitle: S.computerConfig,
              onTap: _openGuide,
            ),
            _EntryTile(
              icon: Icons.new_releases_outlined,
              title: S.updateLog,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: widget.changelogBuilder)),
            ),
            _EntryTile(
              icon: Icons.system_update_alt,
              title: S.checkUpdate,
              onTap: () {
                Navigator.of(context).pop();
                widget.onCheckUpdate();
              },
            ),
            _SectionHeader(S.about),
            ListTile(
              leading: Icon(Icons.info_outline, color: P.textSecondary),
              title: Text(S.about),
              trailing: Text(
                _version ?? S.loading,
                style: TextStyle(color: P.textTertiary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Language radio group; labels render in their own language.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.controller});

  final LanguageController controller;

  @override
  Widget build(BuildContext context) {
    String labelOf(String id) => switch (id) {
      'system' => S.followSystem,
      'zh' => S.simplifiedChinese,
      _ => 'English',
    };
    return RadioGroup<String>(
      groupValue: controller.languageId,
      onChanged: (id) {
        if (id != null) controller.select(id);
      },
      child: Column(
        children: [
          for (final option in kLanguages)
            RadioListTile<String>(
              value: option.id,
              title: Text(labelOf(option.id)),
              activeColor: P.accent,
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          color: P.textTertiary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: P.textSecondary),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(color: P.textTertiary)),
      trailing: Icon(Icons.chevron_right, color: P.textTertiary, size: 20),
      onTap: onTap,
    );
  }
}

/// Shared native theme swatch; height follows content and text scaling.
class ThemeChoiceCard extends StatelessWidget {
  const ThemeChoiceCard({
    super.key,
    required this.spec,
    required this.selected,
    required this.onTap,
  });
  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: selected ? P.accent : P.divider,
        width: selected ? 1.5 : 1,
      ),
    ),
    child: NeuSurface(
      child: Material(
        color: P.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [
                      spec.palette.bg,
                      spec.palette.bg,
                      spec.palette.accent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(spec.name)),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: P.accent),
                ],
              ),
              Text(
                spec.subtitle,
                style: TextStyle(color: P.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

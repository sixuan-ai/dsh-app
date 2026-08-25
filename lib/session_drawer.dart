/// Session drawer, workspace groups, and session management actions.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'composer.dart';
import 'directory_tree_page.dart';
import 'network_diagnostics_page.dart';
import 'pet_page.dart';
import 'session_mode_badge.dart';
import 'settings_center.dart';
import 'src/ai_hub_pages.dart';
import 'social_page.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'src/session_list_projection.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Session drawer
// ---------------------------------------------------------------------------

class SessionDrawer extends StatefulWidget {
  const SessionDrawer({
    super.key,
    required this.state,
    required this.theme,
    required this.language,
    required this.onLogout,
    required this.onNewSession,
    required this.onCheckUpdate,
    required this.onConnectionCenter,
    required this.connectionMode,
    required this.localAvailable,
    required this.updateAvailable,
    required this.socialBaseUrl,
    required this.connectionGuideBuilder,
    required this.changelogBuilder,
  });

  final AppState state;
  final ThemeController theme;
  final LanguageController language;
  final VoidCallback onLogout;

  /// Opens the new-session directory picker (HomePage owns the context).
  final VoidCallback onNewSession;

  /// Runs a manual update check (HomePage owns the context).
  final VoidCallback onCheckUpdate;
  final VoidCallback onConnectionCenter;
  final String connectionMode;
  final bool localAvailable;

  /// A newer release exists; shows a green dot on 检查更新.
  final bool updateAvailable;
  final String socialBaseUrl;
  final WidgetBuilder connectionGuideBuilder;
  final WidgetBuilder changelogBuilder;

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  /// Workspace keys (cwd) the user collapsed; persisted across launches.
  final Set<String> _collapsed = {};

  /// 0: active list, 1: running, 2: archived, 3: pinned.
  int _sessionFilter = 0;

  /// Cached social profile for the header (nickname + avatar).
  Map<String, dynamic>? _profile;
  String? _profileRaw;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('socialProfile');
    if (raw != _profileRaw && mounted) {
      _profileRaw = raw;
      setState(() {
        _profile = raw == null
            ? null
            : (jsonDecode(raw) as Map).cast<String, dynamic>();
      });
    }
  }

  Future<void> _openCommunity() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityPage(
          state: state,
          // Social backend is centralized on the main domain for all instances.
          socialBaseUrl: widget.socialBaseUrl,
        ),
      ),
    );
    if (mounted) await _loadProfile();
  }

  /// Permission-mode switcher: a sheet of presets riding the host's
  /// /permission command (the same write path as the web Access chip), with
  /// a risk confirmation before danger-full-access.
  Future<void> _openPermissions() async {
    if (state.selectedSessionId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先选择或新建一个会话')));
      return;
    }
    final preset = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => PermissionSheet(
        onPick: (preset) => Navigator.of(sheetContext).pop(preset),
      ),
    );
    if (preset == null || !mounted) return;
    if (preset == 'danger-full-access') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(S.enableFullAccess),
          content: Text(S.fullAccessWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.enable),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await state.runCommand('/permission $preset');
  }

  /// The "更多功能" grid sheet. Pages (pet/changelog) close the drawer first;
  /// sub-sheets (theme/permissions) stay over the open drawer.
  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _MoreSheet(
        actions: [
          _MoreAction(
            icon: Icons.settings_outlined,
            label: S.settings,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsCenterPage(
                    language: widget.language,
                    theme: widget.theme,
                    state: state,
                    socialBaseUrl: widget.socialBaseUrl,
                    onConnectionCenter: widget.onConnectionCenter,
                    onCheckUpdate: widget.onCheckUpdate,
                    connectionGuideBuilder: widget.connectionGuideBuilder,
                    changelogBuilder: widget.changelogBuilder,
                  ),
                ),
              );
            },
          ),
          _MoreAction(
            icon: Icons.alt_route,
            label: S.connectionSafety,
            caption: S.localRemote,
            onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onConnectionCenter();
            },
          ),
          _MoreAction(
            icon: Icons.menu_book_outlined,
            label: S.connectionTutorial,
            caption: S.computerConfig,
            onTap: () {
              Navigator.of(sheetContext).pop();
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: widget.connectionGuideBuilder,
              );
            },
          ),
          _MoreAction(
            icon: Icons.palette_outlined,
            label: S.theme,
            caption: kAppThemes
                .firstWhere(
                  (s) => s.id == widget.theme.themeId,
                  orElse: () => kAppThemes.first,
                )
                .name,
            onTap: () {
              Navigator.of(sheetContext).pop();
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => _ThemeSheet(theme: widget.theme),
              );
            },
          ),
          _MoreAction(
            icon: Icons.newspaper_outlined,
            label: S.aiDaily,
            caption: S.realtimeFeed,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiNewsPage()),
              );
            },
          ),
          _MoreAction(
            icon: Icons.school_outlined,
            label: S.aiLearning,
            caption: S.agentTutorial,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiLearningPage()),
              );
            },
          ),
          _MoreAction(
            icon: Icons.pets,
            label: S.pet,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PetPage(state: state)),
              );
            },
          ),
          _MoreAction(
            icon: Icons.folder_open_outlined,
            label: S.directoryBrowse,
            caption: S.computerDirectories,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DirectoryTreePage(directoryLoader: state.listDirectory),
                ),
              );
            },
          ),
          _MoreAction(
            icon: Icons.network_check_rounded,
            label: S.networkDiagnosis,
            caption: S.latencyJitter,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NetworkDiagnosticsPage(state: state),
                ),
              );
            },
          ),
          _MoreAction(
            icon: Icons.shield_outlined,
            label: S.permissionMode,
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openPermissions();
            },
          ),
          // OTA 自更新仅 Android;iOS 分发必须走 App Store / TestFlight。
          if (defaultTargetPlatform == TargetPlatform.android)
            _MoreAction(
              icon: Icons.system_update_alt,
              label: S.checkUpdate,
              dot: widget.updateAvailable,
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pop();
                widget.onCheckUpdate();
              },
            ),
          _MoreAction(
            icon: Icons.new_releases_outlined,
            label: S.updateLog,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: widget.changelogBuilder));
            },
          ),
          _MoreAction(
            icon: Icons.logout,
            label: S.logout,
            danger: true,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              widget.onLogout();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('collapsedWorkspaces');
    if (saved != null && mounted) {
      setState(() => _collapsed.addAll(saved));
    }
  }

  Future<void> _toggleCollapsed(String key) async {
    setState(() {
      _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('collapsedWorkspaces', _collapsed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(
      state.serverUrl.isEmpty
          ? widget.socialBaseUrl.replaceFirst(RegExp(r'/social$'), '')
          : state.serverUrl,
    ).host;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: P.brandGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileHeader(),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: P.onAccent, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'xHarness',
                        style: TextStyle(
                          color: P.onAccent,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 12,
                        color: P.onAccent.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          host,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: P.onAccent.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.sessions.length} 个会话',
                    style: TextStyle(
                      color: P.onAccent.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LevelBadge(level: state.userLevel),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onNewSession();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建会话'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _filterChip(0, '会话'),
                  _filterChip(1, '运行中'),
                  _filterChip(3, '置顶'),
                  _filterChip(2, '已归档'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _groupedSessionTiles(context),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.groups_outlined, size: 20),
              title: const Text('社区', style: TextStyle(fontSize: 14)),
              onTap: _openCommunity,
            ),
            // Everything else lives in the grid sheet, so the session list
            // keeps the full remaining height no matter how many utilities
            // the app grows.
            ListTile(
              leading: const Icon(Icons.apps_rounded, size: 20),
              title: const Text('更多功能', style: TextStyle(fontSize: 14)),
              trailing:
                  widget.updateAvailable &&
                      defaultTargetPlatform == TargetPlatform.android
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: P.success,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
              onTap: _openMore,
            ),
          ],
        ),
      ),
    );
  }

  /// Social identity row at the top of the drawer header; hidden until the
  /// user joined the community once. Taps through to the community page.
  Widget _profileHeader() {
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    // Avatar URLs live on the centralized social backend (main domain).
    final base = widget.socialBaseUrl.replaceFirst(RegExp(r'/social$'), '');
    final userId = profile['userId'] as String? ?? '';
    final nickname = profile['nickname'] as String? ?? '';
    final ver = (profile['avatarVer'] as num?)?.toInt() ?? 0;
    final token = profile['token'] as String? ?? '';
    final headers = <String, String>{
      if ((state.authUsername ?? '').isNotEmpty)
        'authorization':
            'Basic ${base64Encode(utf8.encode('${state.authUsername}:${state.authPassword ?? ''}'))}',
      'x-social-token': token,
    };
    return InkWell(
      onTap: _openCommunity,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            if (ver > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  '$base/social/avatar?userId=$userId&v=$ver',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  headers: headers,
                  errorBuilder: (_, _, _) => _letterAvatar(nickname),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : _letterAvatar(nickname),
                ),
              )
            else
              _letterAvatar(nickname),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: P.onAccent,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Lv.${profile['level']} · ${profile['title']}',
                    style: TextStyle(
                      color: P.onAccent.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: P.onAccent.withValues(alpha: 0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _letterAvatar(String nickname) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        nickname.isEmpty ? '?' : nickname.characters.first,
        style: TextStyle(
          color: P.onAccent,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _filterChip(int value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _sessionFilter == value,
        onSelected: (_) => setState(() => _sessionFilter = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// Groups filtered sessions by workspace directory (cwd), mirroring the
  /// web client; sessions without one collect in an 未分组 section.
  List<Widget> _groupedSessionTiles(BuildContext context) {
    final groups = projectSessionGroups(
      sessions: state.sessions,
      archivedSessionIds: state.archivedSessionIds,
      pinnedSessionIds: state.pinnedSessionIds,
      filter: SessionListFilter.values[_sessionFilter],
    );
    final tiles = <Widget>[];
    for (final entry in groups.entries) {
      final key = entry.key;
      final rows = entry.value;
      tiles.add(_workspaceHeader(key, rows.length));
      if (!_collapsed.contains(key)) {
        for (final row in rows) {
          tiles.add(_sessionTile(context, row));
        }
      }
    }
    return tiles;
  }

  Widget _workspaceHeader(String cwd, int count) {
    final parts = cwd.split('/').where((s) => s.isNotEmpty).toList();
    final name = cwd.isEmpty ? '未分组' : (parts.isEmpty ? cwd : parts.last);
    final collapsed = _collapsed.contains(cwd);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleCollapsed(cwd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Icon(
                collapsed
                    ? Icons.keyboard_arrow_right
                    : Icons.keyboard_arrow_down,
                size: 16,
                color: P.accentLight,
              ),
              const SizedBox(width: 2),
              Icon(
                cwd.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
                size: 14,
                color: P.accentLight,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: cwd.isEmpty ? '未分组' : cwd,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.4,
                      color: P.accentLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: 11, color: P.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(BuildContext context, SessionRow row) {
    final selected = row.sessionId == state.selectedSessionId;
    final archived = state.archivedSessionIds.contains(row.sessionId);
    final pinned = state.pinnedSessionIds.contains(row.sessionId);
    final mode = state.sessionModeOf(row.sessionId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? P.accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 18, right: 4),
              leading: Icon(
                archived
                    ? Icons.archive_outlined
                    : pinned
                    ? Icons.push_pin
                    : Icons.circle,
                size: pinned || archived ? 18 : 8,
                color: archived
                    ? P.textTertiary
                    : pinned
                    ? P.accentLight
                    : row.running
                    ? P.success
                    : P.textTertiary,
              ),
              title: Text(
                row.title?.isNotEmpty == true ? row.title! : '新会话',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? P.accentLight : null,
                ),
              ),
              subtitle: Row(
                children: [
                  if (mode != SessionMode.auto) ...[
                    SessionModeBadge(mode: mode, compact: true),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _timeAgo(row.updatedAt),
                    style: TextStyle(fontSize: 11.5, color: P.textTertiary),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                tooltip: '会话操作',
                onSelected: (action) => _sessionAction(row, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: pinned ? 'unpin' : 'pin',
                    child: Text(pinned ? '取消置顶' : '置顶'),
                  ),
                  if (!archived)
                    const PopupMenuItem(value: 'archive', child: Text('归档')),
                ],
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop();
                state.openSession(row.sessionId);
              },
            ),
            if (selected)
              Positioned(
                left: 5,
                top: 11,
                bottom: 11,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: P.brandGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sessionAction(SessionRow row, String action) async {
    if (action == 'pin' || action == 'unpin') {
      await state.setSessionPinned(row.sessionId, action == 'pin');
      return;
    }
    if (action != 'archive' || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('归档会话?'),
        content: Text(
          '归档“${row.title?.isNotEmpty == true ? row.title : '新会话'}”后,它会从默认列表隐藏,可在“已归档”中查看。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await state.archiveSession(row.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('会话已归档')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('归档失败: $error')));
      }
    }
  }
}

/// Theme picker sheet: live-preview cards for each built-in theme. Selection
/// applies instantly (the app root listens to the controller) and persists.
class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.pickTheme,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.appliesInstantly,
                  style: TextStyle(color: P.textTertiary, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    for (final spec in kAppThemes)
                      _ThemeCard(
                        spec: spec,
                        selected: spec.id == theme.themeId,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          theme.select(spec.id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One theme preview card in the picker: a miniature mock of the chat page
/// rendered in that theme's own palette.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = spec.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? palette.accent : P.divider,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // mini app bar
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: palette.brandGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 42,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.text,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // mini assistant line
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: palette.divider, width: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // mini user bubble
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 56,
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: palette.brandGradient,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spec.name,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        spec.subtitle,
                        style: TextStyle(
                          color: palette.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: palette.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, size: 12, color: palette.onAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Level badge with progress bar shown in the drawer header; taps open the
/// level rules dialog.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final UserLevel level;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showLevelRules(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.military_tech, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  'Lv.${level.level} · ${level.title}',
                  style: TextStyle(
                    color: P.onAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${level.count} 次对话',
                  style: TextStyle(
                    color: P.onAccent.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: level.progress,
                minHeight: 5,
                backgroundColor: P.fillMedium,
                valueColor: const AlwaysStoppedAnimation(Colors.amber),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                level.next == null
                    ? '已达最高等级'
                    : '再对话 ${level.remaining} 次升至 Lv.${level.level + 1}',
                style: TextStyle(color: P.textSecondary, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLevelRules(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.military_tech, color: Colors.amber),
            SizedBox(width: 8),
            Text('等级规则'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每发送一条消息计 1 次对话,累计达到阈值即可升级。计数保存在本机。',
                  style: TextStyle(fontSize: 12.5, color: P.textSecondary),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < levelThresholds.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          i + 1 <= level.level
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 14,
                          color: i + 1 <= level.level
                              ? Colors.amber
                              : P.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lv.${i + 1} · ${levelTitles[i]}',
                            style: TextStyle(
                              fontSize: 13,
                              color: i + 1 == level.level
                                  ? Colors.amber
                                  : P.textSecondary,
                              fontWeight: i + 1 == level.level
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Text(
                          '≥ ${levelThresholds[i]} 次',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: P.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// Relative timestamp for session rows.
String _timeAgo(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final mm = time.month.toString().padLeft(2, '0');
  final dd = time.day.toString().padLeft(2, '0');
  return '${time.year}-$mm-$dd';
}

/// One entry of the "更多功能" grid sheet.
class _MoreAction {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.dot = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Small tertiary text under the label (e.g. the current theme name).
  final String? caption;

  /// Green badge dot on the icon (update available).
  final bool dot;

  /// Danger styling (logout).
  final bool danger;
}

/// The "更多功能" bottom sheet: a 4-column icon grid holding every utility
/// that used to be a full-height drawer tile.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.actions});

  final List<_MoreAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        // Scrollable so the grid never overflows the sheet's constrained
        // height on short or wide screens.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '更多功能',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 0.92,
                children: [
                  for (final action in actions) _MoreCell(action: action),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCell extends StatelessWidget {
  const _MoreCell({required this.action});

  final _MoreAction action;

  @override
  Widget build(BuildContext context) {
    final fg = action.danger ? P.danger : P.accentLight;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: action.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: action.danger
                      ? P.danger.withValues(alpha: 0.1)
                      : P.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, size: 22, color: fg),
              ),
              if (action.dot)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: P.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: P.card, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            style: TextStyle(
              fontSize: 12,
              color: action.danger ? P.danger : P.textSecondary,
            ),
          ),
          if (action.caption != null)
            Text(
              action.caption!,
              style: TextStyle(fontSize: 10, color: P.textTertiary),
            ),
        ],
      ),
    );
  }
}

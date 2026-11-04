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
import 'pet_board_page.dart';
import 'session_mode_badge.dart';
import 'settings_center.dart';
import 'src/ai_hub_pages.dart';
import 'social_page.dart';
import 'src/l10n.dart';
import 'src/theme.dart';
import 'src/ui/glass.dart';
import 'src/ui/neumorphic.dart';
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
    this.onAppAccount,
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
  final VoidCallback? onAppAccount;
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

  Future<void> _openPermissions() => showPermissionPicker(context, state);

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
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => AiNewsPage()));
            },
          ),
          _MoreAction(
            icon: Icons.school_outlined,
            label: S.aiLearning,
            caption: S.agentTutorial,
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => AiLearningPage()));
            },
          ),
          _MoreAction(
            icon: Icons.pets_rounded,
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
            icon: Icons.leaderboard_rounded,
            label: '宠物排行榜',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PetBoardPage(state: state),
                ),
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
          if (widget.onAppAccount != null)
            _MoreAction(
              icon: Icons.account_circle_outlined,
              label: state.signedInAccount != null ? '我的思玄账号' : '登录 / 注册',
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pop();
                widget.onAppAccount!();
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
      width: (MediaQuery.sizeOf(context).width - 24).clamp(280, 420),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _profileHeader(),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: P.text, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'xHarness',
                          style: TextStyle(
                            color: P.text,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          size: 12,
                          color: P.text.withValues(alpha: 0.8),
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            state.pairedComputer?.name ?? host,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: P.text.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${state.serverAvailable ? (widget.connectionMode == 'lan' ? '局域网已连接' : '公网已连接') : '离线'} · ${state.sessions.length} 个会话',
                      style: TextStyle(
                        color: P.text.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 10),
                    _LevelBadge(level: state.userLevel),
                  ],
                ),
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
            SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: NeuSegmented<int>(
                values: const {0: '会话', 1: '运行中', 3: '置顶', 2: '已归档'},
                selected: _sessionFilter,
                onSelected: (value) => setState(() => _sessionFilter = value),
              ),
            ),
            SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _groupedSessionTiles(context),
              ),
            ),
            Divider(height: 1),
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
      if ((state.accountUsername ?? '').isNotEmpty)
        'authorization':
            'Basic ${base64Encode(utf8.encode('${state.accountUsername}:${state.accountPassword ?? ''}'))}',
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
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: P.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Lv.${profile['level']} · ${profile['title']}',
                    style: TextStyle(
                      color: P.text.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: P.text.withValues(alpha: 0.8),
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
        color: P.neuShadow.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        nickname.isEmpty ? '?' : nickname.characters.first,
        style: TextStyle(
          color: P.text,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Groups filtered sessions by the server workspace registry (title and
  /// order); sessions no workspace accounts for fall back to cwd buckets.
  List<Widget> _groupedSessionTiles(BuildContext context) {
    final groups = projectSessionGroups(
      sessions: state.sessions,
      workspaces: state.workspaces,
      archivedSessionIds: state.archivedSessionIds,
      pinnedSessionIds: state.pinnedSessionIds,
      filter: SessionListFilter.values[_sessionFilter],
    );
    final tiles = <Widget>[];
    for (final group in groups) {
      tiles.add(_workspaceHeader(group, group.rows.length));
      if (!_collapsed.contains(group.key)) {
        for (final row in group.rows) {
          tiles.add(_sessionTile(context, row));
        }
      }
    }
    return tiles;
  }

  Widget _workspaceHeader(ProjectedGroup group, int count) {
    final collapsed = _collapsed.contains(group.key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleCollapsed(group.key),
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
              SizedBox(width: 2),
              Icon(
                group.isWorkspace
                    ? Icons.folder_outlined
                    : Icons.inbox_outlined,
                size: 14,
                color: P.accentLight,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: group.path ?? '未分组',
                  child: Text(
                    group.title,
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

  Widget _sessionTag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10.5)),
  );

  Widget _sessionTile(BuildContext context, SessionRow row) {
    final selected = row.sessionId == state.selectedSessionId;
    final archived = state.archivedSessionIds.contains(row.sessionId);
    final pinned = state.pinnedSessionIds.contains(row.sessionId);
    final mode = state.sessionModeOf(row.sessionId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: NeuSurface(
        padding: EdgeInsets.zero,
        child: Material(
          color: selected ? P.accent.withValues(alpha: 0.10) : P.transparent,
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
                subtitle: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (state.approvals.any(
                      (a) => a.sessionId == row.sessionId,
                    ))
                      _sessionTag('待审批', P.warning)
                    else if (row.running)
                      _sessionTag('运行中', P.accent),
                    if (mode != SessionMode.auto) ...[
                      SessionModeBadge(mode: mode, compact: true),
                      SizedBox(width: 6),
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
                      PopupMenuItem(value: 'archive', child: Text('归档')),
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
        ).showSnackBar(SnackBar(content: Text('会话已归档')));
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: theme,
    builder: (context, _) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.pickTheme, style: Theme.of(context).textTheme.titleMedium),
              Text(
                S.appliesInstantly,
                style: TextStyle(color: P.textSecondary),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(14) > 18 ? 1 : 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final spec in kAppThemes)
                        SizedBox(
                          width:
                              (constraints.maxWidth - (columns - 1) * 12) /
                              columns,
                          child: ThemeChoiceCard(
                            spec: spec,
                            selected: spec.id == theme.themeId,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              theme.select(spec.id);
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
          color: P.neuShadow.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Icon(Icons.military_tech, size: 16, color: P.warning),
                SizedBox(width: 6),
                Text(
                  'Lv.${level.level} · ${level.title}',
                  style: TextStyle(
                    color: P.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${level.count} 次对话',
                  style: TextStyle(
                    color: P.text.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: level.progress,
                minHeight: 5,
                backgroundColor: P.fillMedium,
                valueColor: AlwaysStoppedAnimation(P.warning),
              ),
            ),
            SizedBox(height: 4),
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
        title: Row(
          children: [
            Icon(Icons.military_tech, color: P.warning),
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
                SizedBox(height: 12),
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
                              ? P.warning
                              : P.textTertiary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lv.${i + 1} · ${levelTitles[i]}',
                            style: TextStyle(
                              fontSize: 13,
                              color: i + 1 == level.level
                                  ? P.warning
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
              SizedBox(height: 12),
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
          SizedBox(height: 6),
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

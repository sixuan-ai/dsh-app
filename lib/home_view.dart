/// Home scaffold with independent AppState rebuild regions.
library;

import 'package:flutter/material.dart';

import 'chat_list.dart';
import 'composer.dart';
import 'quick_start.dart';
import 'session_header.dart';
import 'state.dart';
import 'state_selector.dart';
import 'stats_bar.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.state,
    required this.drawerBuilder,
    required this.onModelPicker,
    required this.onNewSession,
    required this.onRename,
    required this.onRefresh,
    required this.onRetryConnection,
    required this.onConnectionCenter,
    required this.onCheckUpdate,
    required this.onLogout,
    required this.onSuggestion,
    this.connectionWelcomeBuilder,
  });

  final AppState state;
  final WidgetBuilder? connectionWelcomeBuilder;
  final WidgetBuilder drawerBuilder;
  final VoidCallback onModelPicker;
  final VoidCallback onNewSession;
  final VoidCallback onRename;
  final VoidCallback onRefresh;
  final VoidCallback onRetryConnection;
  final VoidCallback onConnectionCenter;
  final VoidCallback onCheckUpdate;
  final VoidCallback onLogout;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AnimatedBuilder(
        animation: state,
        builder: (context, _) => drawerBuilder(context),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: StateSelector<HomeHeaderSelection>(
          listenable: state,
          select: () => HomeHeaderSelection.from(state),
          builder: (context, selection) => SessionHeader(
            state: state,
            title: selection.title,
            subtitleParts: selection.subtitleParts,
            onModelPicker: onModelPicker,
            onNewSession: onNewSession,
            onRename: onRename,
            onRefresh: onRefresh,
            onCheckUpdate: onCheckUpdate,
            onLogout: onLogout,
          ),
        ),
      ),
      body: Column(
        children: [
          AnimatedBuilder(
            animation: state,
            builder: (context, _) =>
                state.hasEntryAccess &&
                    !state.serverAvailable &&
                    state.sessions.isEmpty
                ? const SizedBox.shrink()
                : StatsBar(state: state),
          ),
          AnimatedBuilder(
            animation: state,
            builder: (context, _) => _ConnectionStatusBanner(
              status: state.connectionStatus,
              detail: state.connectionError,
              onRetry: onRetryConnection,
              onConnectionCenter: onConnectionCenter,
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: state,
              builder: (context, _) => state.selectedSessionId == null
                  ? (!state.serverAvailable && connectionWelcomeBuilder != null)
                        ? connectionWelcomeBuilder!(context)
                        : EmptySessionView(
                            onNewSession: onNewSession,
                            onSuggestion: onSuggestion,
                          )
                  : ChatList(state: state),
            ),
          ),
          StateSelector<ComposerSelection>(
            listenable: state,
            select: () => ComposerSelection(
              state.selectedSessionId,
              state.selectedRunning,
              state.serverAvailable,
            ),
            builder: (context, _) =>
                state.hasEntryAccess &&
                    state.selectedSessionId == null &&
                    !state.serverAvailable
                ? const SizedBox.shrink()
                : Composer(state: state),
          ),
        ],
      ),
    );
  }
}

class HomeHeaderSelection {
  const HomeHeaderSelection({
    required this.sessionId,
    required this.title,
    required this.subtitle,
    this.controls = '',
  });

  factory HomeHeaderSelection.from(AppState state) {
    final sessionId = state.selectedSessionId;
    SessionRow? row;
    if (sessionId != null) {
      for (final candidate in state.sessions) {
        if (candidate.sessionId == sessionId) {
          row = candidate;
          break;
        }
      }
    }
    final title = row?.title?.isNotEmpty == true
        ? row!.title!
        : (sessionId == null ? 'xHarness' : '新会话');
    return HomeHeaderSelection(
      sessionId: sessionId,
      title: title,
      controls:
          '${state.loadingModels}:${state.loadingSubagents}:'
          '${state.queuedTasks.length}:'
          '${state.subagents.map((a) => '${a.id}:${a.activity}:${a.label}').join(',')}',
      subtitle: [
        ?state.models?.label,
        if (state.syncingTail) '正在同步最新进度…',
        if (state.fillingHistoryGap) '正在补齐中间历史…',
        if (state.selectedRunning) '正在生成…',
      ].join('\u0000'),
    );
  }

  final String? sessionId;
  final String title;
  final String subtitle;
  final String controls;

  List<String> get subtitleParts =>
      subtitle.isEmpty ? const [] : subtitle.split('\u0000');

  @override
  bool operator ==(Object other) =>
      other is HomeHeaderSelection &&
      sessionId == other.sessionId &&
      title == other.title &&
      subtitle == other.subtitle &&
      controls == other.controls;

  @override
  int get hashCode => Object.hash(sessionId, title, subtitle, controls);
}

class ComposerSelection {
  const ComposerSelection(this.sessionId, this.running, this.serverAvailable);

  final String? sessionId;
  final bool running;
  final bool serverAvailable;

  @override
  bool operator ==(Object other) =>
      other is ComposerSelection &&
      sessionId == other.sessionId &&
      running == other.running &&
      serverAvailable == other.serverAvailable;

  @override
  int get hashCode => Object.hash(sessionId, running, serverAvailable);
}

class _ConnectionStatusBanner extends StatelessWidget {
  const _ConnectionStatusBanner({
    required this.status,
    required this.detail,
    required this.onRetry,
    required this.onConnectionCenter,
  });

  final ServerConnectionStatus status;
  final String? detail;
  final VoidCallback onRetry;
  final VoidCallback onConnectionCenter;

  @override
  Widget build(BuildContext context) {
    if (status == ServerConnectionStatus.online ||
        status == ServerConnectionStatus.idle) {
      return const SizedBox.shrink();
    }
    final isAuth = status == ServerConnectionStatus.authRequired;
    final reconnecting =
        status == ServerConnectionStatus.reconnecting ||
        status == ServerConnectionStatus.connecting;
    final color = reconnecting ? Colors.amber.shade800 : Colors.red.shade700;
    final label = isAuth
        ? '登录状态已失效，请重新连接'
        : reconnecting
        ? '服务连接暂时中断，正在恢复…'
        : '服务暂时不可用，已保留本地内容';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          Icon(
            reconnecting
                ? Icons.sync_problem_outlined
                : Icons.cloud_off_outlined,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: isAuth ? onConnectionCenter : onRetry,
            child: Text(isAuth ? '连接设置' : '立即重试'),
          ),
        ],
      ),
    );
  }
}

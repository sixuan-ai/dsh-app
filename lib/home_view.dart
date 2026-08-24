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
    required this.onCheckUpdate,
    required this.onLogout,
    required this.onSuggestion,
  });

  final AppState state;
  final WidgetBuilder drawerBuilder;
  final VoidCallback onModelPicker;
  final VoidCallback onNewSession;
  final VoidCallback onRename;
  final VoidCallback onRefresh;
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
            builder: (context, _) => StatsBar(state: state),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: state,
              builder: (context, _) => state.selectedSessionId == null
                  ? EmptySessionView(
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
            ),
            builder: (context, _) => Composer(state: state),
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

  List<String> get subtitleParts =>
      subtitle.isEmpty ? const [] : subtitle.split('\u0000');

  @override
  bool operator ==(Object other) =>
      other is HomeHeaderSelection &&
      sessionId == other.sessionId &&
      title == other.title &&
      subtitle == other.subtitle;

  @override
  int get hashCode => Object.hash(sessionId, title, subtitle);
}

class ComposerSelection {
  const ComposerSelection(this.sessionId, this.running);

  final String? sessionId;
  final bool running;

  @override
  bool operator ==(Object other) =>
      other is ComposerSelection &&
      sessionId == other.sessionId &&
      running == other.running;

  @override
  int get hashCode => Object.hash(sessionId, running);
}

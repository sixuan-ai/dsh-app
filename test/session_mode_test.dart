import 'package:dsh_mobile/session_mode_badge.dart';
import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void modeGroup() {
  AppState withProjections(Map<String, dynamic> values) {
    final state = AppState();
    state.projections.putIfAbsent('s1', () => {});
    for (final entry in values.entries) {
      state.projections['s1']![entry.key] = ProjectionCell(entry.value, 1);
    }
    return state;
  }

  test('auto mode when no goal or plan is active', () {
    final state = AppState();
    expect(state.sessionModeOf('s1'), SessionMode.auto);
    // plan projection present but inactive stays auto
    final inactive = withProjections({
      'plan': {'active': false, 'pending': false},
    });
    expect(inactive.sessionModeOf('s1'), SessionMode.auto);
  });

  test('goal mode while a goal is active', () {
    final state = withProjections({
      'goal': {
        'goal': {
          'id': 'goal-1',
          'revision': 1,
          'objective': 'do the thing',
          'phase': 'active',
          'maxGoalRounds': 10,
        },
        'roundsStarted': 1,
      },
    });
    expect(state.sessionModeOf('s1'), SessionMode.goal);
  });

  test('a completed goal falls back to auto', () {
    final state = withProjections({
      'goal': {
        'goal': {
          'id': 'goal-1',
          'revision': 2,
          'objective': 'done',
          'phase': 'complete',
          'maxGoalRounds': 10,
        },
        'roundsStarted': 1,
      },
    });
    expect(state.sessionModeOf('s1'), SessionMode.auto);
  });

  test('plan mode wins while plan is active', () {
    final state = withProjections({
      'plan': {'active': true, 'pending': false},
    });
    expect(state.sessionModeOf('s1'), SessionMode.plan);
  });
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void badgeGroup() {
  testWidgets('badge renders the localized label per mode', (tester) async {
    await tester.pumpWidget(
      _wrap(const SessionModeBadge(mode: SessionMode.goal)),
    );
    expect(find.text(S.modeGoal), findsOneWidget);
    await tester.pumpWidget(
      _wrap(const SessionModeBadge(mode: SessionMode.plan)),
    );
    expect(find.text(S.modePlan), findsOneWidget);
    await tester.pumpWidget(
      _wrap(const SessionModeBadge(mode: SessionMode.auto)),
    );
    expect(find.text(S.modeAuto), findsOneWidget);
  });

  testWidgets('compact badge still shows the label', (tester) async {
    await tester.pumpWidget(
      _wrap(const SessionModeBadge(mode: SessionMode.plan, compact: true)),
    );
    expect(find.text(S.modePlan), findsOneWidget);
  });
}

void main() {
  badgeGroup();
  modeGroup();
}

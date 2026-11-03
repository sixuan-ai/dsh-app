import 'dart:async';

import 'package:dsh_mobile/home_view.dart';
import 'package:dsh_mobile/model_picker.dart';
import 'package:dsh_mobile/session_header.dart';
import 'package:dsh_mobile/src/protocol.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledApi extends DshApi {
  ControlledApi() : super('http://127.0.0.1:1');
  final requests = <Completer<Map<String, dynamic>>>[];
  @override
  Future<dynamic> call(
    String method,
    Map<String, dynamic> payload, {
    String? rpcId,
  }) {
    expect(method, 'session.modelCatalog');
    final request = Completer<Map<String, dynamic>>();
    requests.add(request);
    return request.future;
  }
}

class HistoryRaceApi extends DshApi {
  HistoryRaceApi() : super('http://127.0.0.1:1');
  int historyReads = 0;
  @override
  Future<dynamic> call(
    String method,
    Map<String, dynamic> payload, {
    String? rpcId,
  }) async =>
      method == 'session.modelCatalog' ? catalog('default') : {'entries': []};
  @override
  Future<Map<String, dynamic>> sessionHistory(
    String sessionId, {
    int? beforeSeq,
    int? maxMessages,
  }) async => {
    'events': [
      {'event': historyReads++ == 0 ? callEvent() : result()},
    ],
    'hasMore': false,
  };
  @override
  Stream<dynamic> sessionFollow(String sessionId) => Stream.value({
    'type': 'snapshot',
    'cursor': 2,
    'projections': {'asOfSeq': 2, 'values': {}},
    'records': [
      {'type': 'event', 'event': result()},
    ],
  });
}

Map<String, dynamic> catalog(String model) => {
  'default': {'provider': 'deepseek', 'model': model},
  'routableProviders': ['deepseek'],
  'groups': [
    {
      'id': 'deepseek',
      'name': 'DeepSeek',
      'models': [
        {'id': model, 'name': model},
      ],
    },
  ],
};

void projection(AppState app, int seq, String model, {String? effort}) {
  app.muxFrameForTest(
    ServerFrame(
      rpcId: 'p-$seq',
      method: 'session/projection',
      payload: {
        'type': 'session/projection',
        'sessionId': app.selectedSessionId,
        'key': 'modelSelection',
        'seq': seq,
        'value': {
          'lastUsed': null,
          'next': {
            'provider': 'deepseek',
            'model': model,
            'reasoningEffort': ?effort,
          },
        },
      },
    ),
  );
}

Map<String, dynamic> event(int seq, String type, Map<String, dynamic> data) => {
  'seq': seq,
  'time': 0,
  'type': type,
  'data': data,
};

Map<String, dynamic> callEvent() => event(1, 'tool/call', {
  'callId': 'script-1',
  'name': 'bash',
  'arguments': '{"command":"echo done"}',
});
Map<String, dynamic> result({bool error = false}) => event(2, 'tool/result', {
  'message': {
    'source': {'kind': 'tool', 'callId': 'script-1'},
    'content': [
      {
        'type': 'tool-result',
        'toolCallId': 'script-1',
        'isError': error,
        'content': [
          {'type': 'text', 'text': 'done'},
        ],
      },
    ],
  },
});

void main() {
  test('replayed call-only history cannot downgrade a completed script', () {
    final app = AppState();
    addTearDown(app.dispose);
    app.foldForTest(callEvent());
    app.foldForTest(result());
    final calls = <ChatItem>[];
    app.foldForTest(callEvent(), into: calls);
    app.mergeTailForTest(calls);
    expect(app.items.single.completed, isTrue);
    expect(app.items.single.resultText, 'done');
  });

  test(
    'completion between history read and follow registration repairs the card',
    () async {
      final api = HistoryRaceApi();
      final app = AppState()..attachApiForTest(api, startStreams: false);
      addTearDown(app.dispose);
      await app.openSession('a');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(api.historyReads, 2);
      expect(app.items, hasLength(1));
      expect(app.items.single.name, 'bash');
      expect(app.items.single.completed, isTrue);
      expect(app.items.single.resultText, 'done');
    },
  );

  test(
    'result-only history page settles an earlier script after page merge',
    () {
      final app = AppState();
      addTearDown(app.dispose);
      final results = <ChatItem>[];
      app.foldForTest(result(), into: results);
      expect(results.single.completed, isTrue);
      app.mergeTailForTest(results, firstSeq: 2);
      final calls = <ChatItem>[];
      app.foldForTest(callEvent(), into: calls);
      app.mergeTailForTest(calls);
      expect(app.items, hasLength(1));
      expect(app.items.single.name, 'bash');
      expect(app.items.single.arguments, contains('echo done'));
      expect(app.items.single.completed, isTrue);
      expect(app.items.single.resultText, 'done');
    },
  );

  test(
    'tail repair settles a cached running call, including failed scripts',
    () {
      final app = AppState();
      addTearDown(app.dispose);
      app.foldForTest(callEvent());
      final results = <ChatItem>[];
      app.foldForTest(result(error: true), into: results);
      app.mergeTailForTest(results, firstSeq: 2);
      expect(app.items, hasLength(1));
      expect(app.items.single.completed, isTrue);
      expect(app.items.single.resultIsError, isTrue);
    },
  );

  test(
    'late catalog response cannot overwrite another session or connection',
    () async {
      final api = ControlledApi();
      final app = AppState()..attachApiForTest(api, startStreams: false);
      addTearDown(app.dispose);
      app.selectedSessionId = 'a';
      final first = app.loadModels();
      app.selectedSessionId = 'b';
      final second = app.loadModels();
      api.requests[1].complete(catalog('new'));
      await second;
      api.requests[0].complete(catalog('old'));
      await first;
      expect(app.models!.label, 'new');
      final pending = app.loadModels();
      app.disconnect();
      api.requests[2].complete(catalog('disconnected'));
      await pending;
      expect(app.models, isNull);
      expect(app.loadingModels, isFalse);
    },
  );

  test(
    'selected projection overrides default, follows desktop changes and rejects stale frames',
    () async {
      final api = ControlledApi();
      final app = AppState()
        ..attachApiForTest(api, startStreams: false)
        ..selectedSessionId = 'a';
      addTearDown(app.dispose);
      projection(app, 10, 'chosen', effort: 'high');
      expect(app.models!.label, 'chosen · high');
      final load = app.loadModels();
      api.requests.single.complete(catalog('default'));
      await load;
      expect(app.models!.label, 'chosen · high');
      expect(app.models!.routable, isTrue);
      projection(app, 12, 'desktop');
      projection(app, 11, 'stale');
      expect(app.models!.label, 'desktop');
      expect(app.models!.current.containsKey('reasoningEffort'), isFalse);
      final failed = app.loadModels();
      api.requests.last.completeError(StateError('offline'));
      await failed;
      expect(app.models!.label, 'desktop');
    },
  );

  testWidgets(
    'model sheet updates when catalog arrives and selection changes',
    (tester) async {
      final app = AppState()..selectedSessionId = 'a';
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ModelPickerSheet(state: app)),
        ),
      );
      expect(find.text('模型目录不可用'), findsOneWidget);
      projection(app, 1, 'chosen');
      await tester.pump();
      expect(find.text('当前: chosen'), findsOneWidget);
      projection(app, 2, 'desktop');
      await tester.pump();
      expect(find.text('当前: desktop'), findsOneWidget);
      expect(find.text('当前: chosen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('open subagent sheet follows running-to-inactive host status', (
    tester,
  ) async {
    final app = AppState()
      ..subagents = [
        const SubagentRow(
          id: 'child',
          mode: 'one-shot',
          activity: 'running',
          hasChildren: false,
          label: '脚本任务',
        ),
      ];
    addTearDown(app.dispose);
    final before = HomeHeaderSelection.from(app);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SubagentStatusButton(state: app)),
      ),
    );
    await tester.tap(find.byTooltip('1 个子代理正在工作'));
    await tester.pumpAndSettle();
    expect(find.text('工作中'), findsOneWidget);
    app.hostFrameForTest(
      ServerFrame(
        rpcId: 'status',
        method: 'host/session-status',
        payload: {
          'type': 'host/session-status',
          'sessionId': 'child',
          'running': false,
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('工作中'), findsNothing);
    expect(find.text('已完成'), findsOneWidget);
    expect(HomeHeaderSelection.from(app), isNot(before));
    await tester.pumpWidget(const SizedBox());
  });
}

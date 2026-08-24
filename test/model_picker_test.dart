import 'package:dsh_mobile/model_picker.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows unavailable state without a model catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ModelPickerSheet(state: AppState())),
      ),
    );
    expect(find.text('模型目录不可用'), findsOneWidget);
  });

  testWidgets('renders current model and provider groups', (tester) async {
    final state = AppState()
      ..models = SessionModelsData(
        current: const {'provider': 'deepseek', 'model': 'deepseek-chat'},
        routable: true,
        groups: const [
          {
            'id': 'deepseek',
            'name': 'DeepSeek',
            'models': [
              {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
            ],
          },
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ModelPickerSheet(state: state)),
      ),
    );
    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('当前: deepseek-chat'), findsOneWidget);
    expect(find.text('DeepSeek Chat'), findsOneWidget);
  });

  testWidgets('current model tile carries the accent selection style', (
    tester,
  ) async {
    final state = AppState()
      ..models = SessionModelsData(
        current: const {'provider': 'deepseek', 'model': 'deepseek-chat'},
        routable: true,
        groups: const [
          {
            'id': 'deepseek',
            'name': 'DeepSeek',
            'models': [
              {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
              {'id': 'deepseek-reasoner', 'name': 'DeepSeek Reasoner'},
            ],
          },
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ModelPickerSheet(state: state)),
      ),
    );

    final currentTitle = tester.widget<Text>(find.text('DeepSeek Chat'));
    expect(currentTitle.style?.color, P.accentLight);
    expect(currentTitle.style?.fontWeight, FontWeight.w600);

    final otherTitle = tester.widget<Text>(find.text('DeepSeek Reasoner'));
    expect(otherTitle.style?.color, isNull);
  });
}

import 'package:dsh_mobile/question_dialog.dart';
import 'package:dsh_mobile/src/theme.dart';
import 'package:dsh_mobile/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requires an answer before enabling submit', (tester) async {
    final state = AppState();
    final pending = PendingQuestion(
      rpcId: 'q-1',
      sessionId: 's-1',
      questions: const [
        {
          'id': 'choice',
          'header': '偏好',
          'question': '选择一种颜色',
          'options': [
            {'label': '蓝色', 'description': '冷色'},
          ],
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionDialog(state: state, pending: pending),
        ),
      ),
    );

    final submit = find.widgetWithText(FilledButton, '提交');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('蓝色'));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    final selected = tester.widget<Text>(find.text('蓝色'));
    expect(selected.style?.color, P.accentLight);
    expect(selected.style?.fontWeight, FontWeight.w600);
  });
}

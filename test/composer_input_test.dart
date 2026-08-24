import 'package:dsh_mobile/composer_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('updates send action from localized text value', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var sends = 0;

    Widget build(bool canSend) => MaterialApp(
      home: Scaffold(
        body: ComposerInput(
          controller: controller,
          focusNode: focusNode,
          enabled: true,
          canSend: canSend,
          running: false,
          picking: false,
          canPickImage: true,
          onChanged: (_) {},
          onOpenCommands: () {},
          onPickImage: () {},
          onStop: () {},
          onSend: () => sends++,
        ),
      ),
    );

    await tester.pumpWidget(build(false));
    expect(find.byTooltip('发送'), findsOneWidget);

    await tester.pumpWidget(build(true));
    await tester.tap(find.byTooltip('发送'));
    expect(sends, 1);

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('shows stop beside send while running', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposerInput(
            controller: TextEditingController(),
            focusNode: FocusNode(),
            enabled: true,
            canSend: false,
            running: true,
            picking: false,
            canPickImage: true,
            onChanged: (_) {},
            onOpenCommands: () {},
            onPickImage: () {},
            onStop: () {},
            onSend: () {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
  });
}

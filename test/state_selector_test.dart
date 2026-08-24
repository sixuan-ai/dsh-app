import 'package:dsh_mobile/state_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestState extends ChangeNotifier {
  int selected = 0;
  int unrelated = 0;

  void changeSelected(int value) {
    selected = value;
    notifyListeners();
  }

  void changeUnrelated() {
    unrelated++;
    notifyListeners();
  }
}

void main() {
  testWidgets('rebuilds only when selected value changes', (tester) async {
    final state = TestState();
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StateSelector<int>(
          listenable: state,
          select: () => state.selected,
          builder: (context, value) {
            builds++;
            return Text('$value');
          },
        ),
      ),
    );
    expect(builds, 1);

    state.changeUnrelated();
    await tester.pump();
    expect(builds, 1);

    state.changeSelected(1);
    await tester.pump();
    expect(builds, 2);
    expect(find.text('1'), findsOneWidget);
  });
}

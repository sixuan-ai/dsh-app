import 'package:dsh_mobile/src/l10n.dart';
import 'package:dsh_mobile/state.dart';
import 'package:dsh_mobile/support_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders in-app support channels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SupportPage(
          state: AppState(),
          socialBaseUrl: 'https://example.com/social',
          connectionGuideBuilder: (_) => const SizedBox(),
          changelogBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.supportTitle), findsOneWidget);
    expect(find.text(S.feedback), findsOneWidget);
    expect(find.text(S.feedbackDesc), findsOneWidget);
    expect(find.text(S.community), findsOneWidget);
    expect(find.text(S.communityDesc), findsOneWidget);
    expect(find.text(S.connectionGuide), findsOneWidget);
    expect(find.text(S.updateLog), findsOneWidget);
  });
}

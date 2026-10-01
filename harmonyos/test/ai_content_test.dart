import 'package:dsh_mobile/src/ai_content.dart';
import 'package:dsh_mobile/src/ai_hub_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI news uses a 10:00-to-10:00 news day', () {
    final morning = DateTime(2026, 8, 23, 9);
    final afterBoundary = DateTime(2026, 8, 23, 10);
    expect(aiNewsDay(morning), DateTime(2026, 8, 23));
    expect(aiNewsDay(afterBoundary), DateTime(2026, 8, 24));

    final items = [
      AiNewsItem(
        id: 'morning',
        title: 'Morning',
        summary: '',
        content: '',
        category: '新模型',
        tags: const [],
        sourceName: 'Official',
        sourceUrl: '',
        publishedAt: '2026-08-23T09:00:00',
      ),
      AiNewsItem(
        id: 'after-boundary',
        title: 'After boundary',
        summary: '',
        content: '',
        category: '新模型',
        tags: const [],
        sourceName: 'Official',
        sourceUrl: '',
        publishedAt: '2026-08-23T10:00:00',
      ),
    ];

    expect(aiNewsOnNewsDay(items, DateTime(2026, 8, 23)).single.id, 'morning');
    expect(
      aiNewsOnNewsDay(items, DateTime(2026, 8, 24)).single.id,
      'after-boundary',
    );
  });

  test('latest closed news day does not expose an unfinished 10:00 day', () {
    expect(
      aiLatestClosedNewsDay(DateTime(2026, 8, 23, 9)),
      DateTime(2026, 8, 22),
    );
    expect(
      aiLatestClosedNewsDay(DateTime(2026, 8, 23, 10)),
      DateTime(2026, 8, 23),
    );
  });
}

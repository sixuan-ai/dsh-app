import 'package:dsh_mobile/src/ai_content.dart';
import 'package:dsh_mobile/src/ai_hub_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI news groups entries by local publication date', () {
    const items = [
      AiNewsItem(
        id: 'today',
        title: 'Today',
        summary: '',
        content: '',
        category: '新模型',
        tags: [],
        sourceName: 'Official',
        sourceUrl: '',
        publishedAt: '2026-08-23T08:00:00Z',
      ),
      AiNewsItem(
        id: 'yesterday',
        title: 'Yesterday',
        summary: '',
        content: '',
        category: '新模型',
        tags: [],
        sourceName: 'Official',
        sourceUrl: '',
        publishedAt: '2026-08-22T08:00:00Z',
      ),
    ];

    expect(aiNewsOnDate(items, DateTime(2026, 8, 23)).single.id, 'today');
    expect(aiNewsOnDate(items, DateTime(2026, 8, 22)).single.id, 'yesterday');
    expect(aiNewsOnDate(items, DateTime(2026, 8, 21)), isEmpty);
  });
}

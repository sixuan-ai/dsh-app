import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const kAiNewsUrl = 'https://dsh.ainotex.com/app/content/ai/news.json';
const kAiAgentsUrl = 'https://dsh.ainotex.com/app/content/ai/agents.json';

class AiNewsItem {
  const AiNewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.category,
    required this.tags,
    required this.sourceName,
    required this.sourceUrl,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String summary;
  final String content;
  final String category;
  final List<String> tags;
  final String sourceName;
  final String sourceUrl;
  final String publishedAt;

  factory AiNewsItem.fromJson(Map<String, dynamic> json) => AiNewsItem(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    content: json['content'] as String? ?? '',
    category: json['category'] as String? ?? 'AI',
    tags: (json['tags'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    sourceName: json['sourceName'] as String? ?? 'xHarness',
    sourceUrl: json['sourceUrl'] as String? ?? '',
    publishedAt: json['publishedAt'] as String? ?? '',
  );
}

class AiAgentItem {
  const AiAgentItem({
    required this.id,
    required this.name,
    required this.type,
    required this.release,
    required this.focus,
    required this.install,
    required this.quickStart,
    required this.url,
    required this.icon,
    required this.note,
  });

  final String id;
  final String name;
  final String type;
  final String release;
  final String focus;
  final String install;
  final String quickStart;
  final String url;
  final String icon;
  final String note;

  factory AiAgentItem.fromJson(Map<String, dynamic> json) => AiAgentItem(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? '',
    release: json['release'] as String? ?? '',
    focus: json['focus'] as String? ?? '',
    install: json['install'] as String? ?? '',
    quickStart: json['quickStart'] as String? ?? '',
    url: json['url'] as String? ?? '',
    icon: json['icon'] as String? ?? 'smart_toy',
    note: json['note'] as String? ?? '',
  );
}

class AiContentResult<T> {
  const AiContentResult({
    required this.items,
    required this.fromCache,
    this.updatedAt,
  });
  final List<T> items;
  final bool fromCache;
  final String? updatedAt;
}

class AiContentRepository {
  const AiContentRepository();

  Future<AiContentResult<AiNewsItem>> loadNews() => _load(
    url: kAiNewsUrl,
    cacheKey: 'aiNewsContent',
    parser: AiNewsItem.fromJson,
  );

  Future<AiContentResult<AiAgentItem>> loadAgents() => _load(
    url: kAiAgentsUrl,
    cacheKey: 'aiAgentContent',
    parser: AiAgentItem.fromJson,
  );

  Future<AiContentResult<T>> _load<T>({
    required String url,
    required String cacheKey,
    required T Function(Map<String, dynamic>) parser,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = _parseItems(decoded, parser);
      if (items.isEmpty) throw const FormatException('empty content');
      await prefs.setString(cacheKey, response.body);
      return AiContentResult(
        items: items,
        fromCache: false,
        updatedAt: decoded['updatedAt'] as String?,
      );
    } catch (_) {
      final cached = prefs.getString(cacheKey);
      if (cached == null) rethrow;
      final decoded = jsonDecode(cached) as Map<String, dynamic>;
      return AiContentResult(
        items: _parseItems(decoded, parser),
        fromCache: true,
        updatedAt: decoded['updatedAt'] as String?,
      );
    }
  }

  List<T> _parseItems<T>(
    Map<String, dynamic> decoded,
    T Function(Map<String, dynamic>) parser,
  ) => (decoded['items'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(parser)
      .toList();
}

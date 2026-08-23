import 'package:flutter/material.dart';

import 'ai_content.dart';
import 'theme.dart';

/// Returns the local calendar date portion used to group website news.
String aiNewsDateKey(String publishedAt) {
  final parsed = DateTime.tryParse(publishedAt)?.toLocal();
  if (parsed == null) return '';
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day';
}

/// Selects news published on one local calendar date.
List<AiNewsItem> aiNewsOnDate(List<AiNewsItem> items, DateTime date) {
  final key = aiNewsDateKey(date.toIso8601String());
  return items.where((item) => aiNewsDateKey(item.publishedAt) == key).toList();
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Website-backed AI news page with cached offline fallback.
class AiNewsPage extends StatefulWidget {
  const AiNewsPage({super.key});

  @override
  State<AiNewsPage> createState() => _AiNewsPageState();
}

class _AiNewsPageState extends State<AiNewsPage> {
  final _repository = const AiContentRepository();
  List<AiNewsItem> _items = const [];
  bool _loading = true;
  bool _fromCache = false;
  String? _error;
  final PageController _pageController = PageController(initialPage: 3650);
  final DateTime _today = _dateOnly(DateTime.now());
  int _page = 3650;

  DateTime get _selectedDate => _today.add(Duration(days: _page - 3650));

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.loadNews();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _fromCache = result.fromCache;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法加载网站内容，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI 新闻'),
      actions: [
        IconButton(
          tooltip: '刷新新闻',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PageIntro(
            icon: Icons.newspaper_outlined,
            title: 'AI 新闻',
            subtitle: '由 xHarness 网站统一整理和发布',
          ),
          const SizedBox(height: 12),
          _ContentStatus(fromCache: _fromCache, loading: _loading),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: P.textSecondary)),
          ],
          const SizedBox(height: 12),
          _NewsDateToolbar(
            date: _selectedDate,
            isToday: _page == 3650,
            onToday: () => _pageController.animateToPage(
              3650,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 520,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (_, page) {
                final date = _today.add(Duration(days: page - 3650));
                final todayItems = aiNewsOnDate(_items, date);
                final yesterdayItems = aiNewsOnDate(
                  _items,
                  date.subtract(const Duration(days: 1)),
                );
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _NewsSection(
                      title: '${_formatDate(date)} 最新',
                      items: todayItems,
                    ),
                    const SizedBox(height: 10),
                    _NewsSection(
                      title:
                          '${_formatDate(date.subtract(const Duration(days: 1)))} 昨日回顾',
                      items: yesterdayItems,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Website-backed AI agent learning page with cached offline fallback.
class AiLearningPage extends StatefulWidget {
  const AiLearningPage({super.key});

  @override
  State<AiLearningPage> createState() => _AiLearningPageState();
}

class _AiLearningPageState extends State<AiLearningPage> {
  final _repository = const AiContentRepository();
  List<AiAgentItem> _items = const [];
  bool _loading = true;
  bool _fromCache = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.loadAgents();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _fromCache = result.fromCache;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法加载网站内容，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI 知识学习'),
      actions: [
        IconButton(
          tooltip: '刷新知识库',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PageIntro(
            icon: Icons.school_outlined,
            title: 'AI 知识学习',
            subtitle: '由 xHarness 网站统一整理和发布',
          ),
          const SizedBox(height: 12),
          _ContentStatus(fromCache: _fromCache, loading: _loading),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: P.textSecondary)),
          ],
          const SizedBox(height: 14),
          for (final agent in _items) _AgentCard(agent: agent),
        ],
      ),
    ),
  );
}

class _PageIntro extends StatelessWidget {
  const _PageIntro({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: P.brandGradient,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: P.onAccent, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: P.onAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: P.onAccent.withValues(alpha: 0.86),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ContentStatus extends StatelessWidget {
  const _ContentStatus({required this.fromCache, required this.loading});
  final bool fromCache;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: P.fillSubtle,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          loading
              ? Icons.sync_outlined
              : fromCache
              ? Icons.cloud_off_outlined
              : Icons.cloud_done_outlined,
          size: 17,
          color: P.accentLight,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            loading
                ? '正在从 xHarness 网站加载…'
                : fromCache
                ? '网站暂时不可用，当前显示上次缓存内容。'
                : '内容由 xHarness 网站统一发布。',
            style: TextStyle(color: P.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

String _formatDate(DateTime date) => '${date.month}月${date.day}日';

class _NewsDateToolbar extends StatelessWidget {
  const _NewsDateToolbar({
    required this.date,
    required this.isToday,
    required this.onToday,
  });
  final DateTime date;
  final bool isToday;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.swipe_outlined, size: 17),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          '${_formatDate(date)} · 左右滑动切换日期',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      if (!isToday) TextButton(onPressed: onToday, child: const Text('回到今天')),
    ],
  );
}

class _NewsSection extends StatelessWidget {
  const _NewsSection({required this.title, required this.items});
  final String title;
  final List<AiNewsItem> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          title,
          style: TextStyle(
            color: P.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (items.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: P.fillSubtle,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '这一天暂时没有发布新闻',
            textAlign: TextAlign.center,
            style: TextStyle(color: P.textTertiary, fontSize: 12.5),
          ),
        )
      else
        for (final item in items) _NewsCard(item: item),
    ],
  );
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});
  final AiNewsItem item;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ExpansionTile(
      title: Text(
        item.title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text('${item.category} · ${item.sourceName}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(
          item.summary,
          style: TextStyle(color: P.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 8),
        Text(
          item.content,
          style: TextStyle(color: P.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 8),
        Text(
          item.sourceUrl,
          style: TextStyle(color: P.accentLight, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          item.publishedAt,
          style: TextStyle(color: P.textTertiary, fontSize: 11),
        ),
      ],
    ),
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final AiAgentItem agent;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      leading: Icon(_agentIcon(agent.icon), color: P.accentLight),
      title: Text(
        agent.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(agent.type),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _InfoLine(label: '发布时间', value: agent.release),
        _InfoLine(label: '主要面向', value: agent.focus),
        _CodeBlock(label: '安装', value: agent.install),
        _CodeBlock(label: '快速开始', value: agent.quickStart),
        if (agent.note.isNotEmpty) _InfoLine(label: '注意', value: agent.note),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            agent.url,
            style: TextStyle(color: P.accentLight, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

IconData _agentIcon(String name) => switch (name) {
  'auto_awesome' => Icons.auto_awesome,
  'code' => Icons.code_rounded,
  'extension' => Icons.extension_outlined,
  'hub' => Icons.hub_outlined,
  'psychology' => Icons.psychology_alt_outlined,
  _ => Icons.smart_toy_outlined,
};

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: RichText(
      text: TextSpan(
        style: TextStyle(color: P.textSecondary, height: 1.4),
        children: [
          TextSpan(
            text: '$label：',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: P.fillSubtle,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: P.textTertiary, fontSize: 11)),
        const SizedBox(height: 5),
        SelectableText(
          value,
          style: TextStyle(
            color: P.text,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

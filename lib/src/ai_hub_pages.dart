import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'theme.dart';

/// Curated entry for an AI agent or model platform.
class AiAgentEntry {
  const AiAgentEntry({
    required this.name,
    required this.type,
    required this.release,
    required this.focus,
    required this.install,
    required this.quickStart,
    required this.url,
    required this.icon,
    this.note,
  });

  final String name;
  final String type;
  final String release;
  final String focus;
  final String install;
  final String quickStart;
  final String url;
  final IconData icon;
  final String? note;
}

const _agents = [
  AiAgentEntry(
    name: 'Claude Code',
    type: '商业终端编码 Agent',
    release: '2025-02-24 公布',
    focus: '代码库理解、文件修改、命令执行、测试和故障排查',
    install: 'curl -fsSL https://claude.ai/install.sh | bash',
    quickStart: 'cd your-project\nclaude',
    url: 'https://code.claude.com/docs/en/overview',
    icon: Icons.auto_awesome,
    note: '需要 Anthropic 账户或 API 访问权限。首次使用前请确认文件和命令权限。',
  ),
  AiAgentEntry(
    name: 'Codex CLI',
    type: 'OpenAI 终端编码 Agent',
    release: '2025-04 公开发布',
    focus: '代码修改、测试、代码审查和仓库任务',
    install: 'npm install -g @openai/codex',
    quickStart: 'cd your-project\ncodex',
    url: 'https://github.com/openai/codex',
    icon: Icons.code_rounded,
    note: '可使用 ChatGPT 登录或 OpenAI API；安装后建议运行 codex --version。',
  ),
  AiAgentEntry(
    name: 'Pi Coding Agent',
    type: '可扩展终端编码 Agent',
    release: '持续开源发布，暂无统一首发日',
    focus: '模型切换、扩展、自定义工作流和开发者工具构建',
    install: 'npm install -g @mariozechner/pi-coding-agent',
    quickStart: 'cd your-project\npi',
    url: 'https://github.com/badlogic/pi-mono',
    icon: Icons.extension_outlined,
    note: '需要配置模型供应商和凭据；第三方扩展请只安装可信来源。',
  ),
  AiAgentEntry(
    name: 'OpenClaw',
    type: '个人 AI 助手与 Agent 平台',
    release: '持续开源更新，暂无统一首发日',
    focus: '长期会话、工具调用、消息渠道和个人自动化',
    install: 'curl -fsSL https://openclaw.ai/install.sh | bash',
    quickStart: 'openclaw onboard',
    url: 'https://openclaw.ai/',
    icon: Icons.hub_outlined,
    note: '可能配置后台 gateway 和消息渠道；部署前请检查监听地址、令牌和权限。',
  ),
  AiAgentEntry(
    name: 'DeepSeek',
    type: '模型与 API 平台',
    release: 'V3：2024-12-26 · R1：2025-01-20',
    focus: '为其他 Agent 提供推理、代码生成和工具调用能力',
    install: 'export DEEPSEEK_API_KEY="你的密钥"',
    quickStart: 'pip install openai\n# 然后按 API 文档配置模型',
    url: 'https://api-docs.deepseek.com/zh-cn/',
    icon: Icons.psychology_alt_outlined,
    note: 'DeepSeek 是模型/API 提供方，不等同于拥有本地文件和命令权限的 Agent。',
  ),
  AiAgentEntry(
    name: 'Hermes Agent',
    type: '开源通用终端 Agent',
    release: '持续开源开发，暂无统一首发日',
    focus: '代码、浏览器任务、命令执行、记忆和多模型后端',
    install:
        'git clone https://github.com/NousResearch/hermes-agent.git\ncd hermes-agent\n./setup.sh',
    quickStart: 'hermes',
    url: 'https://hermes-agent.nousresearch.com/docs/',
    icon: Icons.smart_toy_outlined,
    note: '首次安装可能需要 Python、系统工具和模型供应商凭据，建议在隔离工作目录运行。',
  ),
];

/// News item displayed by the AI news page.
class AiNewsItem {
  const AiNewsItem({
    required this.title,
    required this.summary,
    required this.source,
    required this.url,
    required this.date,
  });

  final String title;
  final String summary;
  final String source;
  final String url;
  final String date;
}

const _news = [
  AiNewsItem(
    title: 'AI Agent 工具生态持续扩展',
    summary:
        'Claude Code、Codex CLI、Pi、OpenClaw 与 Hermes Agent 分别覆盖编码、自动化和多渠道助手场景。',
    source: 'xHarness AI 观察',
    url: 'https://github.com/NousResearch/hermes-agent',
    date: '近期',
  ),
  AiNewsItem(
    title: 'DeepSeek API 继续服务 Agent 集成',
    summary: 'DeepSeek 可作为模型后端接入终端 Agent 和自建工具系统，使用时应单独配置模型权限与本地工具权限。',
    source: 'DeepSeek API',
    url: 'https://api-docs.deepseek.com/zh-cn/',
    date: '近期',
  ),
  AiNewsItem(
    title: '从终端编码到个人助手',
    summary: 'AI Agent 的使用边界正在从代码仓库扩展到浏览器、消息渠道、知识检索和长期任务。',
    source: 'xHarness AI 观察',
    url: 'https://openclaw.ai/',
    date: '近期',
  ),
];

class AiNewsPage extends StatefulWidget {
  const AiNewsPage({super.key});

  @override
  State<AiNewsPage> createState() => _AiNewsPageState();
}

class _AiNewsPageState extends State<AiNewsPage> {
  List<AiNewsItem> _items = _news;
  bool _loading = true;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final live = await _fetchNews();
      if (mounted && live.isNotEmpty) {
        setState(() {
          _items = live;
          _online = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _online = false);
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
          _PageIntro(
            icon: Icons.newspaper_outlined,
            title: 'AI 新闻',
            subtitle: '关注模型、Agent 和开发工具的最新动态',
          ),
          const SizedBox(height: 12),
          _NewsSourceNote(online: _online, loading: _loading),
          const SizedBox(height: 12),
          for (final item in _items) _NewsCard(item: item),
        ],
      ),
    ),
  );
}

Future<List<AiNewsItem>> _fetchNews() async {
  const feeds = [
    ('Anthropic', 'https://www.anthropic.com/rss.xml'),
    ('OpenAI', 'https://openai.com/news/rss.xml'),
    ('DeepSeek', 'https://api-docs.deepseek.com/news/rss.xml'),
  ];
  final items = <AiNewsItem>[];
  for (final feed in feeds) {
    try {
      final response = await http
          .get(Uri.parse(feed.$2))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) continue;
      final document = XmlDocument.parse(response.body);
      for (final entry in document.findAllElements('item').take(4)) {
        final title = entry.getElement('title')?.innerText.trim();
        final link = entry.getElement('link')?.innerText.trim();
        final summary = entry.getElement('description')?.innerText.trim();
        if (title == null || title.isEmpty || link == null || link.isEmpty) {
          continue;
        }
        items.add(
          AiNewsItem(
            title: title,
            summary: summary == null || summary.isEmpty
                ? '查看来源了解最新动态。'
                : summary.replaceAll(RegExp(r'<[^>]*>'), ''),
            source: feed.$1,
            url: link,
            date: '实时',
          ),
        );
      }
    } catch (_) {
      continue;
    }
  }
  return items;
}

class AiLearningPage extends StatelessWidget {
  const AiLearningPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 知识学习')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PageIntro(
          icon: Icons.school_outlined,
          title: 'AI 知识学习',
          subtitle: '了解不同 Agent 的定位、安装方式和适用工作',
        ),
        const SizedBox(height: 14),
        for (final agent in _agents) _AgentCard(agent: agent),
      ],
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

class _NewsSourceNote extends StatelessWidget {
  const _NewsSourceNote({required this.online, required this.loading});

  final bool online;
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
              : online
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          size: 17,
          color: P.accentLight,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            loading
                ? '正在聚合官方 RSS…'
                : online
                ? '已显示来自官方 RSS 的最新内容，下拉可刷新。'
                : '网络源暂不可用，当前显示内置精选内容。',
            style: TextStyle(color: P.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});
  final AiNewsItem item;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                item.date,
                style: TextStyle(color: P.textTertiary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            item.summary,
            style: TextStyle(color: P.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            '${item.source} · ${item.url}',
            style: TextStyle(color: P.accentLight, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final AiAgentEntry agent;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      leading: Icon(agent.icon, color: P.accentLight),
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
        if (agent.note != null) _InfoLine(label: '注意', value: agent.note!),
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

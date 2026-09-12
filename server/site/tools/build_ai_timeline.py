"""Build a dependency-free, progressively enhanced editorial timeline."""
from pathlib import Path
from html import escape as h
import json
root = Path(__file__).resolve().parents[1]
# Dates follow the cited publication; month precision is retained when appropriate.
rows = [
('2017-06-12','Transformer','研究基础','国际','论文发表','注意力机制成为基础架构','以注意力机制构建序列转换模型，为后续语言模型提供重要架构基础。','架构论文，不对应单一大模型参数量','https://arxiv.org/abs/1706.03762'),
('2018-10-11','BERT','研究基础','国际','论文发表','双向预训练推动语言理解','通过双向上下文预训练，再针对下游任务微调，推动问答与文本理解研究。','编码器架构；本卡不比较模型规模','https://arxiv.org/abs/1810.04805'),
('2020-05-28','GPT-3','模型','国际','论文发表','从微调走向上下文学习','在提示中提供少量示例，无需更新模型权重即可执行多种语言任务。','最大版本 175B · 稠密模型','https://arxiv.org/abs/2005.14165'),
('2022-10-06','ReAct','Agent','国际','论文发表','让推理与行动交替进行','将推理过程与外部环境操作结合，利用观察结果调整后续行动，是理解 Agent 工作循环的重要研究。','方法框架 · 无独立参数量','https://arxiv.org/abs/2210.03629'),
('2022-11-30','ChatGPT','模型','国际','研究预览','对话成为大众使用 AI 的入口','基于 GPT-3.5 系列，结合人类反馈训练，以多轮对话提供回答、写作与代码协助。','发布资料未公开准确参数量','https://openai.com/index/chatgpt/'),
('2023-03-14','GPT-4','模型','国际','模型发布','语言模型迈向多模态','发布支持文本与图像输入、文本输出的模型；图像能力在发布时仍有使用范围限制。','未公开 · 不采用网络推测值','https://openai.com/index/gpt-4-research/'),
('2024-05-13','GPT-4o','模型','国际','模型发布','文本、视觉与音频统一建模','面向跨模态交互设计；发布展示的能力与分阶段开放的产品功能需要区分。','未公开 · 多模态模型','https://openai.com/index/hello-gpt-4o/'),
('2024-07-23','Llama 3.1','模型','国际','模型发布','开放权重扩展到 405B','提供 8B、70B、405B 版本，支持 128K 上下文，为本地与云端部署提供不同规模选择。','8B / 70B / 405B · 稠密；遵循 Llama 许可','https://ai.meta.com/blog/meta-llama-3-1/'),
('2024-09-19','Qwen2.5','模型','国内','模型发布','中文与多语言模型形成规模梯度','系列覆盖不同参数规模，并发展代码、数学等专门模型，便于按算力与任务选择。','0.5B–72B · 系列版本许可需分别核对','https://qwenlm.github.io/blog/qwen2.5/'),
('2024-11-25','Model Context Protocol','MCP','国际','协议发布','为 AI 连接数据与工具建立共同接口','Anthropic 发布 MCP，让 AI 应用通过统一协议接入内容仓库、业务工具与开发环境。','协议 · 无模型参数；不等同于 Agent 本身','https://www.anthropic.com/news/model-context-protocol'),
('2024-12-27','DeepSeek-V3','模型','国内','技术报告发表','MoE 与训练效率受到关注','通过混合专家架构、MLA 与负载均衡设计探索大模型训练效率。本节点日期为技术报告首发日期。','总参数 671B · 每 token 激活 37B','https://arxiv.org/abs/2412.19437'),
('2025-01-22','DeepSeek-R1','模型','国内','论文发表','强化学习推动推理能力','研究强化学习如何激发推理行为，并提供蒸馏模型。此处记录论文首发，非模型上线日。','主模型总参数 671B · 每 token 激活 37B；蒸馏版另计','https://arxiv.org/abs/2501.12948'),
('2025-02-24','Claude Code','CLI','国际','研究预览','Agent 进入真实代码仓库','随 Claude 3.7 Sonnet 发布研究预览，通过终端理解代码、编辑文件并运行开发任务。','编程 Agent / CLI · 参数取决于底层模型','https://www.anthropic.com/news/claude-3-7-sonnet'),
('2025-04-16','Codex CLI','CLI','国际','工具发布','将编程 Agent 带入命令行','OpenAI 发布开源终端编程工具，将模型能力接入本地开发工作流。工具本地运行不代表模型本地推理。','编程 Agent / CLI · 无独立模型参数','https://openai.com/index/introducing-o3-and-o4-mini/'),
('2025-04-29','Qwen3','模型','国内','模型发布','思考模式与非思考模式结合','同时提供稠密与 MoE 模型；可按任务选择思考方式，覆盖从轻量到大规模的部署需求。','旗舰总参数 235B / 激活 22B；另有 30B / 3B','https://qwenlm.github.io/blog/qwen3/'),
('2025-06-25','Gemini CLI','CLI','国际','工具发布','终端 AI 工具生态继续扩展','Google 发布开源命令行 Agent，将 Gemini 接入代码开发、内容生成与问题解决流程。','终端 Agent · 无独立模型参数','https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemini-cli-open-source-ai-agent/'),
('2025-08-07','GPT-5','模型','国际','模型发布','推理与编程进入统一产品体验','发布面向聊天与开发者的模型体系，强调推理、代码和工具使用；产品系统与单个 API 模型需区分。','未公开 · 不以产品名称推断架构规模','https://openai.com/index/introducing-gpt-5/'),
('2025-11-18','Gemini 3','模型','国际','模型预览','多模态理解与 Agent 能力演进','Google 发布 Gemini 3 Pro 预览，将新一代推理和多模态能力带入 Gemini 与开发工具。','未公开 · 本节点记录 Pro 预览','https://blog.google/products-and-platforms/products/gemini/gemini-3/'),
('2026-02-05','Claude Opus 4.6','模型','国际','模型发布','更长任务与更大代码库','加强编程、审查与调试能力；发布时为 Opus 系列引入 1M token 上下文测试版。','未公开 · 1M 指上下文 token 数，不是参数量','https://www.anthropic.com/news/claude-opus-4-6'),
('2026-02','Qwen3.5','模型','国内','模型发布 · 月级日期','原生视觉语言与混合架构','公开旗舰 Qwen3.5-397B-A17B，结合视觉语言能力与混合架构；日期按官方模型卡月份记录。','总参数 397B · 每 token 激活 17B','https://huggingface.co/Qwen/Qwen3.5-397B-A17B'),
]
data = [dict(zip(('date','title','category','region','event','headline','description','parameters','source'),r)) for r in rows]
# Month-only entries sort before specific days in that month: no invented day.
data.sort(key=lambda x:x['date'], reverse=True)
(root/'ai-timeline/events.json').write_text(json.dumps({'reviewedAt':'2026-09-08','scope':'精选历史节点，非完整发布日志','events':data}, ensure_ascii=False, indent=2)+'\n')
years = sorted({r['date'][:4] for r in data},reverse=True)
sections=[]
for year in years:
    cards=[]
    for e in data:
        if not e['date'].startswith(year): continue
        tags=e['category'] + (' Agent' if e['category']=='CLI' else '')
        cards.append(f'''<article class="event" data-category="{h(tags)}" data-region="{h(e['region'])}">
<div class="meta"><span class="badge { 'domestic' if e['region']=='国内' else '' }">{h(e['category'])} · {h(e['region'])}</span><time datetime="{e['date']}">{e['date'].replace('-','.')}</time></div>
<p class="event-kind">{h(e['event'])}</p><h3>{h(e['title'])}</h3><p class="headline">{h(e['headline'])}</p><p class="description">{h(e['description'])}</p><div class="parameters"><span>参数 / 技术规格</span><p>{h(e['parameters'])}</p></div><a class="source" href="{h(e['source'])}" target="_blank" rel="noopener noreferrer">官方来源 / 原始论文 ↗<span class="sr-only">：{h(e['title'])}</span></a></article>''')
    sections.append(f'<section class="year-group" id="year-{year}" aria-labelledby="heading-{year}"><h2 id="heading-{year}">{year}<span>{len(cards)} 个节点</span></h2><div class="cards">'+''.join(cards)+'</div></section>')
html='''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AI 大事记 — 模型、Agent 与工具的发展 | 思玄科技</title><meta name="description" content="通过时间线与事件卡片了解大模型、国内外模型发布、参数规模，以及 Agent、MCP 和 CLI 的发展。每个节点附官方来源。"><link rel="icon" href="/logo.png"><link rel="canonical" href="https://ainotex.com/ai-timeline/"><meta name="color-scheme" content="light dark"><meta name="theme-color" content="#eef0f4"><script src="/assets/appearance.js?v=3"></script><link rel="stylesheet" href="style.css?v=2"><script src="timeline.js?v=2" defer></script></head>
<body><a class="skip" href="#timeline">跳到时间线</a><header><div class="wrap top"><a class="brand" href="/"><img src="/logo.png" alt=""><span>思玄科技</span></a><nav aria-label="主导航"><a href="/">返回首页</a><a href="/ai-timeline/" aria-current="page">AI 大事记</a></nav><div class="theme-switch" role="group" aria-label="外观模式"><button type="button" data-theme-choice="light" aria-pressed="false" title="浅色模式"><span aria-hidden="true">☀</span><span class="theme-label">浅色</span></button><button type="button" data-theme-choice="dark" aria-pressed="false" title="深色模式"><span aria-hidden="true">☾</span><span class="theme-label">深色</span></button><button type="button" data-theme-choice="system" aria-pressed="true" title="跟随系统"><span aria-hidden="true">◐</span><span class="theme-label">自动</span></button></div></div></header>
<main class="wrap"><section class="hero"><p class="eyebrow"><span class="live-dot" aria-hidden="true"></span> 思玄 · AI CHRONICLE</p><h1>记录 AI 的每一次<span>重要跨越。</span></h1><p class="lead">从理解语言，到理解世界，再到调用工具完成任务。<br>沿着时间线，探索模型、方法与开发工具如何走到今天。</p><div class="hero-bottom"><p><span class="mini-orbit" aria-hidden="true">✦</span> 2017 — 2026 <span>精选技术发展史</span></p><a href="#timeline">浏览 20 个里程碑 ↓</a></div></section>
<section class="guide" aria-label="阅读指南"><div><b>01 / 模型</b><p>理解与生成的能力基础。参数规模、架构和训练方式共同影响表现。</p></div><div><b>02 / Agent</b><p>围绕目标规划、调用工具，再根据结果继续行动的应用系统。</p></div><div><b>03 / MCP & CLI</b><p>MCP 统一工具连接方式；CLI 是命令行入口，二者可以共同服务 Agent。</p></div></section>
<details class="editorial"><summary>关于这份大事记 <span>数据来源与参数口径</span></summary><p><strong>阅读口径</strong>　B = 10 亿参数；MoE 分列总参数与每 token 激活参数。上下文长度不等于参数量，参数多也不直接等于能力强。工具与协议没有独立模型参数。</p><p>资料核对：2026.09.08 · 精选条目覆盖至 2026 年 2 月，并非实时新闻或完整发布清单。日期遵循来源，论文日期与产品发布日分别标注；参数与功能描述对应所列历史版本。</p></details>
<section id="timeline" aria-label="AI 发展时间线"><div class="timeline-heading"><div><p class="eyebrow">EXPLORE THE TIMELINE</p><h2>沿时间，见演进</h2></div><p id="result-count" role="status">20 个历史节点 · 从新到旧</p></div>
<form id="filters" hidden role="search"><div class="filter-row"><label>类别<select id="category"><option value="all">全部类别</option><option>模型</option><option>研究基础</option><option>Agent</option><option>MCP</option><option>CLI</option></select></label><label>地区<select id="region"><option value="all">国内与国际</option><option>国内</option><option>国际</option></select></label><label class="search">搜索<input id="query" type="search" placeholder="搜索模型、工具、技术关键词" autocomplete="off"></label><button type="reset">重置</button></div></form>
<nav class="years" aria-label="按年份跳转">YEAR_LINKS</nav><div id="events">SECTIONS</div><p id="empty" hidden>没有匹配的节点，试试其他关键词或重置筛选。</p></section>
<footer><span>© 2026 思玄科技 · AI 技术观察</span><a href="/">返回公司首页 ↗</a></footer></main></body></html>'''
html=html.replace('YEAR_LINKS',''.join(f'<a href="#year-{y}">{y}</a>' for y in years)).replace('SECTIONS',''.join(sections))
(root/'ai-timeline/index.html').write_text(html+'\n')
print(f'Generated {len(data)} sourced events across {len(years)} years')

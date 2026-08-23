# xHarness AI 内容发布

App 和官网共用本目录中的内容数据：

- `news.json`：AI 新闻
- `agents.json`：AI Agent 知识与安装教程

## 发布流程

1. 编辑 JSON，增加或修改内容。
2. 保持顶层 `version` 单调递增，并更新 `updatedAt`。
3. 校验 JSON：

   ```bash
   python3 -m json.tool news.json >/dev/null
   python3 -m json.tool agents.json >/dev/null
   ```

4. 上传到生产网站：

   ```bash
   scp -r content/ai root@47.239.235.154:/var/www/dsh-site/content/
   ```

5. 验证：

   ```bash
   curl -fsS https://dsh.ainotex.com/app/content/ai/news.json | python3 -m json.tool
   curl -fsS https://dsh.ainotex.com/app/content/ai/agents.json | python3 -m json.tool
   ```

App 只读取本站数据，不直接请求任何第三方新闻源。网络失败时显示最近一次成功获取的缓存内容。

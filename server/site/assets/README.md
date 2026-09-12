# 公司官网外观

- `site-design.css`：公司首页、xHarness、secagent、mars-ubuntu 的共享外观层，在各页面原有布局样式之后加载。
- `appearance.js`：官网与 AI 大事记共用的主题逻辑。localStorage 键 `sixuan-appearance`，取值 light / dark / system。
- AI 大事记保留独立布局样式；修改其 HTML 请编辑 `../tools/build_ai_timeline.py` 后重新生成。
- 更新资源时同步调整 HTML 查询版本。发布仅同步明确列出的 HTML、CSS、JS，不同步此说明或构建工具。

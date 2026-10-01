# Design — README 介绍页与 site MVP

## Boundaries

| 层 | 职责 |
|----|------|
| `README.md` | 介绍页：定位、场景、能力摘要、竞品差异短表、证据链接、最短上手、指向站点 |
| `site/` | 操作与参考：上手详解、公开 API、CLI、持久化、注入点、评测/Benchmark、安全与限制 |
| `docs/project|resources` | 既有长文（PRD/架构/竞品报告）；站点与 README **链接**，不复制全文 |

## README 建议骨架（精简）

1. 标题 + badges + 一句话定位  
2. 解决什么问题（1 短段 + 1 场景）  
3. 核心能力（要点列表，不展开机制）  
4. 相对竞品 / 生态（短表：PowerMem、moon-agent 内存记忆、跨语言 mem0 类——钉差异，不写论文）  
5. 证据：Benchmark 站内页 + LoCoMo 报告链接  
6. 最短上手（依赖说明 + 十行内 `open/add/recall`）  
7. 文档入口（Guide / API / Benchmark）+ 仓库结构一行级概览（可选极短）

**迁出到 site 的现有章节：** 公开 API 表、注入点表、LLM 注入长示例、持久化布局、CLI 全表、示例命令全集、测试与评测命令、项目结构细表、安全边界长文、已知限制长文。

## Site 信息架构（MVP）

| 路径 | 内容来源 |
|------|----------|
| `site/docs/index.md` | 中文首页 hero + 3～4 个 feature 卡，链 Guide/API/Benchmark |
| `site/docs/guide/start/introduction.md` | 项目介绍（与 README 同叙事，可略详） |
| `site/docs/guide/start/getting-started.md` | 安装、最短代码、CLI 快速演示、链 API |
| `site/docs/guide/start/persistence.md`（新建） | 双槽布局与状态机（自 README 迁出） |
| `site/docs/guide/start/security.md`（新建） | 安全边界与已知限制（自 README 迁出） |
| `site/docs/api/index.mdx` | MemoryStore 公开 API + 注入点 |
| `site/docs/api/commands.mdx` 或改名为 CLI | CLI 命令与环境变量 |
| `site/docs/api/llm.md`（新建，可选） | LLM 注入示例（若不想塞进 API overview） |
| `site/docs/benchmark/index.mdx` | 保留并补中文导语 + 如何本地跑/看归档（命令可简） |
| 删除 | `site/docs/guide/use-mdx/**` |

侧栏：`guide/_meta.json` 只保留 `start`；`start/_meta.json` 列出 introduction / getting-started / persistence / security。  
顶栏：`_nav.json` 去掉链到 rspress.rs 的 Document；GitHub 指向 `glimverge/moomem`。  
`rspress.config.ts`：`title: moomem`，`socialLinks` → 本仓库；`lang` 可保持或改为与中文内容一致（不强制 i18n 基建）。

## Tradeoffs

- **新建少量 Guide 页 vs 全塞 getting-started**：拆 persistence/security 避免上手页过长。  
- **竞品不进站内长页**：减少维护；深读者走 `docs/resources/`。  
- **不在本任务美化 logo**：继续用现有 public 图标或纯文字 hero。

## Compatibility

- 仅文档与站点配置；不改 `src/` 行为。  
- GitHub Pages `base: '/moomem/'` 保持不变。

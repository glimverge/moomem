# README 介绍页与文档站分流

## Goal

把根目录 `README.md` 收敛为**项目介绍页**；把 API / CLI / 持久化 / 评测等**参考细节**迁入中文 `site/` 文档站（MVP），去掉 Rspress 模板噪声。

## Background

当前 README 约 280 行，介绍与手册混杂。站点已有 Guide / API / Benchmark 导航，但首页与大量指南仍是 Rspress 占位。产品是 MoonBit 嵌入式 Agent 持久化记忆层；相对 PowerMem（需部署）、moon-agent BufferMemory（不持久）等，差异在「嵌入式零部署 + 多后端 + 结构级用户隔离」。

## Decisions

| ID | 决策 | 选择 |
|----|------|------|
| D1 | 语言 | README 与 `site/` 正文**中文**（标识符英文） |
| D2 | 站点深度 | **MVP**：首页 + Guide 介绍/上手；细节进现有 API·Guide·Benchmark；竞品短段在 README，深文链 `docs/resources/` |
| D3 | 模板页 | **删除** `site/docs/guide/use-mdx/**` 并从侧栏清除 |

## Requirements

- **R1** README 介绍：做什么、场景、核心能力、相对竞品/生态差异、证据入口、最短上手、链到站点
- **R2** 参考级内容落入 `site/`，README 只链过去
- **R3** 不做价值单主题专文，也不面面俱到
- **R4** 首页与 Guide 起步页中文、叙事与 README 一致；修正 rspress 外链与站点标题
- **R5** 删除 `use-mdx` 模板树并更新 `_meta` / `_nav`
- **R6** 范围止于 D2 MVP

## Acceptance Criteria

- [x] AC1：README 读完能回答用途、场景、差异、证据入口、如何开始；不再含完整 API/CLI/持久化/评测手册体
- [x] AC2：上述手册内容在 `site/` 有对应页，且 README 可点到
- [x] AC3：首页 / Guide 介绍为中文非模板；`rspress.config.ts` 与 `_nav` 指向本仓库 / 本站；无 `use-mdx` 入口
- [x] AC4：无 LICENSE / CONTRIBUTING / CHANGELOG 专章堆砌

## Out of scope

- 独立竞品长页；重写 `docs/project/*`；LoCoMo/CI 行为变更；品牌 logo

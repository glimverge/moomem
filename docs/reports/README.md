# 项目文档索引

moomem 全生命周期文档（选题调研 → 竞品复核 → PRD → 进度规划 → 独立验证），与架构文档同源于 2026 MoonBit 黑客松十月赛开发过程。FlowUs 云端镜像存于「临界微光」工作区的「moomem · MoonBit 黑客松（十月赛）」页面下。

## 阅读顺序

| # | 文档 | 说明 |
|---|------|------|
| 01 | [选题调研报告 v1.0](01-topic-research.md) | ⚠️ 历史文档：四线调研（语言/赛事/生态/竞品）与六维选题框架；其 moonpatch 推荐已被 v2 推翻，仅作方法论留档 |
| 02 | [竞品分析与生态复核报告 v2.0](02-competitive-analysis.md) | **当前有效版本**：MoonBit vs Rust/Go/TS 对比、mooncakes 生态复核、九轮查重，确认 Agent 持久化记忆为唯一空位 |
| 03 | [产品需求文档 PRD v1.1](03-prd.md) | 22 章 implementation-ready PRD；含 FR-01~10、AC-01~07 验收标准、四周里程碑、风险登记册与 Q1/Q2 决议 |
| 04 | [进度与规划（2026-10-01）](04-progress-and-roadmap.md) | 里程碑进度（W1–W3.1 与 W4 harness 完成、v0.2.2 待发布）、P0~P3 后续规划、验收六条对照 |
| 05 | [测试用例体系（2026-10-01）](05-test-suite.md) | L0~L3 四层测试体系（现网 114/101×3）：离线门禁 / Mock LLM / Live LLM / 基准评测，及 AC 映射 |
| 06 | [W3 独立验证报告（2026-10-01）](06-w3-qa-verification.md) | W3 交付的独立复验：验收项逐条实测、四项实测发现（含相似度实测数据）、偏离项裁定 |
| 07 | [W3.1 独立验证报告（2026-10-01）](07-w3.1-verification.md) | W3.1 补丁复验：A/B/C 三项实证、DoD 逐条复现、两项 P3 残留（R1 代理环境分类；R2 已随 W4-0 修复）与最小修复建议 |
| 08 | [W4 LoCoMo L3 评测报告（2026-10-01）](08-w4-eval-report.md) | PRD §16.1 五项指标离线实测与达标判定：冲突/持久化/隔离达标，检索待 `--embedder api` 档、提取待 `--live` 档 |

另有架构设计文档 [`../architecture.md`](../architecture.md)（模块划分、注入点、双槽快照持久化）及配套 Mermaid 图（类图 / add·recall 时序）。

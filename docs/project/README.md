# moomem · MoonBit 黑客松（十月赛）

> 项目：MoonBit 嵌入式 Agent 记忆层库 —— 参赛 2026 MoonBit 黑客松十月赛。验收截止 2026-10-31。
> 本目录对应 FlowUs「1 · 项目」下的 moomem 容器页，收纳项目主体文档（架构 / PRD / 进度 / 测试 / 验证 / 交接）。

## 子文档

| # | 文档 | 说明 |
|---|------|------|
| — | [架构设计](architecture.md) | 模块划分、注入点、双槽快照持久化（含类图 / add·recall 时序图） |
| 03 | [产品需求文档 PRD v1.1](03-prd.md) | 22 章 implementation-ready PRD；FR-01~10、AC-01~07、四周里程碑、Q1/Q2 决议 |
| 04 | [进度与规划（2026-10-01）](04-progress-and-roadmap.md) | 里程碑进度、P0~P3 后续规划、验收六条对照 |
| 05 | [测试用例体系](05-test-suite.md) | L0~L3 用例编目与 AC 映射（现网 115/102×3）；架构权威见 10 |
| 06 | [W3 独立验证报告](06-w3-qa-verification.md) | W3 交付的独立复验：四项实测发现（含相似度实测数据） |
| 07 | [W3.1 独立验证报告](07-w3.1-verification.md) | W3.1 补丁复验：A/B/C 实证、R1/R2 残留 |
| 08 | [W4 LoCoMo L3 评测报告](08-w4-eval-report.md) | PRD §16.1 五项指标三档实测：4 达标 1 未达标（检索 −12.0% 已归因） |
| 09 | [项目交接总结](09-handover.md) | 首个开发日收官交接：资产地图、架构、时间线、操作手册、协作模式 |
| 10 | [测试与示例能力架构](10-testing-examples-architecture.md) | 测试/门禁/评测/调参/演示落点权威：决策树、现行目录与命令 |

## 外部入口

- GitHub 仓库：<https://github.com/glimverge/moomem>
- mooncakes 包页：<https://mooncakes.io/docs/heyq02/moomem>
- 立项依据：[竞品分析与生态复核报告 v2.0](../resources/02-competitive-analysis.md)（位于 `resources/`，对应 FlowUs 3 · 资源）

## 移出规则

赛季验收结束（或终止）后，本目录对应内容整体迁入 [`../archive/`](../archive/)（对应 FlowUs 4 · 归档），不拆散。

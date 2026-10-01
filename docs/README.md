# moomem 文档索引

本目录是 moomem 项目的文档单一事实源，结构对齐 FlowUs 工作区的 **PARA** 组织方式（0 索引 / 1 项目 / 3 资源 / 4 归档），云端镜像存于 FlowUs「临界微光」工作区。两处数字以仓库为准，改动先改仓库再同步 FlowUs。

## Where to look（三棵文档树，勿混淆）

仓库里有三套并行、各有用途的文档；**不要合并**，按意图选一处：

| 你要找… | 去哪里 | 不是… |
|---------|--------|-------|
| 产品叙事、架构设计、PRD、进度、验证/评测报告、交接 | [`docs/project/`](project/)（本树） | 编码细则或 CI 验收条款 |
| 测试 / 门禁 / 评测 / 调参 / 示例**落点**（决策树、目标目录） | [`project/10-testing-examples-architecture.md`](project/10-testing-examples-architecture.md) | [`05-test-suite`](project/05-test-suite.md) 用例编目 |
| 功能/流程验收契约（W3/W4 AC、CI·发布流水线规格） | [`spec/`](../spec/) | Trellis AI 改代码规则 |
| AI / 维护者改 `src/` 前的包层约定与编码规范 | [`.trellis/spec/`](../.trellis/spec/)（尤其 `library/`） | 产品 PRD 正文 |

调研立项材料在 [`resources/`](resources/)；赛季归档目标在 [`archive/`](archive/)。

## 结构与 FlowUs 对照

| 目录 | 对应 FlowUs 位置 | 内容 |
|------|-----------------|------|
| [`project/`](project/README.md) | 1 · 项目 → 「moomem · MoonBit 黑客松（十月赛）」容器页 | 项目主体文档：架构设计、PRD、进度规划、测试体系、验证报告、交接总结 |
| [`resources/`](resources/README.md) | 3 · 资源 → 选题调研 / 竞品分析两页 | 立项依据与调研材料（决策支持，非执行文档） |
| [`archive/`](archive/README.md) | 4 · 归档 | 赛季验收结束后的整体迁移目标（暂空） |

## 阅读顺序

| # | 文档 | 位置 |
|---|------|------|
| 01 | [选题调研报告 v1.0（历史文档）](resources/01-topic-research.md) | resources |
| 02 | [竞品分析与生态复核报告 v2.0](resources/02-competitive-analysis.md) | resources |
| 03 | [产品需求文档 PRD v1.1](project/03-prd.md) | project |
| 04 | [进度与规划（2026-10-01）](project/04-progress-and-roadmap.md) | project |
| 05 | [测试用例体系](project/05-test-suite.md) | project |
| 06 | [W3 独立验证报告](project/06-w3-qa-verification.md) | project |
| 07 | [W3.1 独立验证报告](project/07-w3.1-verification.md) | project |
| 08 | [W4 LoCoMo L3 评测报告](project/08-w4-eval-report.md) | project |
| 09 | [项目交接总结](project/09-handover.md) | project |
| 10 | [测试与示例能力架构](project/10-testing-examples-architecture.md) | project |
| — | [架构设计](project/architecture.md)（含类图 / add·recall 时序图） | project |

## docs 之外的文档类资产

- [`spec/`](../spec/)：功能/流程验收契约（feature：W3 / W3.1 / W4；process：CI·发布流水线）——与 `.trellis/spec` 分工见上方「Where to look」
- [`.trellis/spec/`](../.trellis/spec/)：AI 编码约定（目录结构、错误/持久化/测试等层规）——改核心库前先读
- [`ci/eval/locomo/data/README.md`](../ci/eval/locomo/data/README.md)：评测数据资产说明（LoCoMo 派生切片，CC BY-NC 4.0）

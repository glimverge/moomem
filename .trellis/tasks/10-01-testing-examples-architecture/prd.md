# 测试与示例能力架构规划

## Goal

产出「测试 & 示例」能力的权威架构规范（分层、落点、决策树、CI 铁律、目标态目录蓝图），作为后续一步到位物理重构（C）的唯一输入。本任务只做规范收敛（A），不搬家、不新写示例业务代码；A 验收后再拆子任务落地 C。

## Background

仓库已有 L0–L3 用例编目（`docs/project/05-test-suite.md`），但能力边界与目录职责不够可执行：包内测试、`examples/`、`ci/{llm_live,locomo,tuning}` 混用「测试 / 门禁 / 评测 / 调参 / 演示」语义。`ci/tuning` 已确认**无任何 CI 调用**，属本地工具。

**铁律（保留）**：L0/L1 永不读 `DEEPSEEK_*`；L2 永不并入 push CI。

## Decisions

| ID | 决策 |
|----|------|
| D1 | 本任务 = **A（规范优先）** |
| D2 | 终极目标 = **C（目录大重构）**；A 完成后再拆子任务 |
| D3 | 子任务在本任务 A 验收后用 `--parent` 创建 |
| D4 | 目标骨架 = **T1**：包旁测试保留；治 `ci/*` 与 `examples` |
| D5 | `ci/tuning` = **U1 开发者工具**（非正式 L 层，不进 CI） |
| D6 | `ci/` 目标命名 = **N2 角色子树**（一步到位，不迁就现名） |
| D7 | 叶子路径 = `ci/gates/live-llm`、`ci/eval/locomo`、`ci/tools/retrieval-tuning` |
| D8 | 权威文档 = `docs/project/10-testing-examples-architecture.md`；`05` 用例编目 + 回链；spec 同步 |
| D9 | `examples/` = **E2 场景子包**；不满足于单一 demo |
| D10 | E2 必选四场景：`basic-store`、`llm-extractor`、`conflict-supersede`、`cli-smoke` |

## Requirements

- R1. 新建 `docs/project/10-testing-examples-architecture.md`：能力分类、落点、命令、CI、铁律、决策树、现状→目标态对照、子任务拆分建议。
- R2. 同步 `.trellis/spec/library/directory-structure.md` 与 `quality-guidelines.md`（可执行 where-to-put / 验证命令表）。
- R3. 决策树覆盖：无 LLM 单测、Mock LLM、Live LLM gate、评测、示例、调参工具。
- R4. 目标态蓝图一步到位（T1+N2+L2+E2+D10）；对照表可机械映射旧→新；标明本任务不迁移。
- R5. 本任务 diff 不破坏现有 `moon test` / workflow 入口（允许 docs/spec 变更）。
- R6. `05-test-suite.md` 与 docs 索引回链到 10，避免双权威架构叙述。
- R7. 蓝图声明 E2 四场景与迁移后 smoke 矩阵意图；**不**在本任务实现示例代码或改 CI 路径。
- R8. 收尾给出建议子任务 slug/边界（创建动作可另开回合）。

## Acceptance Criteria

- [x] AC1. `10-testing-examples-architecture.md` 为架构权威；仅凭该页可知新能力落点、命令、CI。
- [x] AC2. `directory-structure` + `quality-guidelines` 与架构对齐（含决策表）。
- [x] AC3. 含现状→目标态对照（含 D7 三路径与 D10 四 examples），并写明迁移归子任务。
- [x] AC4. 含可执行子任务拆分建议（slug / 边界）。
- [x] AC5. 无无故破坏 `moon test` / 现有 workflow 入口。
- [x] AC6. `05` 与 docs 索引回链到 10；无互相矛盾的第二套架构叙述。

## Out of Scope

- 目录重排、包路径迁移、workflow 改路径
- 新写四场景示例业务代码
- 新增业务 AC 用例集；改 L2/L3 阈值或评测语料
- 把 `retrieval-tuning` 接入 CI（除非未来显式子任务）

## Suggested child tasks（A 验收后）

| 建议 slug | 边界 |
|-----------|------|
| `migrate-ci-role-tree` | `ci/*` → `gates/live-llm`、`eval/locomo`、`tools/retrieval-tuning` + workflow/README 命令同步 |
| `expand-examples-e2` | 落地四场景子包 + smoke 矩阵；迁入现有 llm demo |
| `align-docs-after-migrate` | 迁移后扫尾：05 路径、handover、architecture.md、spec 命令字符串与旧链接 |

## Notes

- 复杂任务：需 `design.md` + `implement.md`；`implement.jsonl` / `check.jsonl` 需真实 spec 条目后再 `task.py start`。

# 迁移 ci 角色子树

## Goal

将 `ci/llm_live`、`ci/locomo`、`ci/tuning` 一步迁移到目标路径 `ci/gates/live-llm`、`ci/eval/locomo`、`ci/tools/retrieval-tuning`，并同步 workflow / 脚本 / README 中的可执行命令，使门禁与评测在新路径下可跑。

## Background

父任务 `.trellis/tasks/10-01-testing-examples-architecture`（A）已锁定蓝图：D6/D7/N2/L2。本子任务只搬 `ci/*` 与命令引用，不改 examples，不改 L2/L3 断言语义。

## Requirements

- R1. `git mv`（或等价）完成三包迁移到目标路径；旧路径不再存在。
- R2. 更新包内硬编码相对路径（如 locomo 默认 fixture `ci/locomo/data/...` → `ci/eval/locomo/data/...`）与注释中的 `moon run` 行。
- R3. 更新 `.github/workflows/test-pipeline.yml` 的 `eval-locomo` job、`scripts/ci/run-llm-live-gate.sh`，以及 README 中现行命令为新路径。
- R4. 离线验证：`moon run ci/eval/locomo --target native` 出 `LOCOMO_PASS`；`moon run ci/tools/retrieval-tuning --target native` 出 `TUNING_PASS`。`ci/gates/live-llm` 至少能编译/`moon check`（无密钥时不强制 LIVE_LLM_PASS）。
- R5. 不把 retrieval-tuning 接入 CI；不改 examples。

## Acceptance Criteria

- [ ] AC1. 目标三目录存在且含原包内容；`ci/llm_live`、`ci/locomo`、`ci/tuning` 已移除。
- [ ] AC2. test-pipeline `eval-locomo` 与 run-llm-live-gate 使用新路径。
- [ ] AC3. README 主命令表使用新路径（或明确指向 doc 10）。
- [ ] AC4. `moon run ci/eval/locomo` 与 `moon run ci/tools/retrieval-tuning` 离线通过。
- [ ] AC5. 未改 examples 布局；未将 tools 接入 push CI。

## Out of Scope

- E2 四场景示例（下一子任务）
- 历史验证报告全文改写（第三子任务 `align-docs-after-migrate`）
- 改评测阈值 / 语料内容

## Depends

- 父任务 A 蓝图已完成（doc 10）。
- 下一子任务 `expand-examples-e2` 依赖本任务完成后再改 smoke 中与 ci 无关的 examples 命令；本任务可暂留 `moon run examples`。

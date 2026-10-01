# 落地 E2 四场景示例

## Goal

将 `examples/` 从单包 demo 拆成四个场景子包：`basic-store`、`llm-extractor`、`conflict-supersede`、`cli-smoke`；全部零网络 mock；更新 CI smoke 为四场景矩阵（或等价全部可跑）。

## Requirements

- R1. 四个 `examples/<scene>/` 包均可 `moon run examples/<scene> --target native`。
- R2. 现有 `llm_extractor_demo` 内容迁入 `examples/llm-extractor`；删除旧单包入口（或变为不存在的顶层 examples main）。
- R3. `basic-store`：缺省无 LLM 主路径演示。
- R4. `conflict-supersede`：可见的冲突/supersede 教学编排（可用 AlwaysReplace 或 mock judge）。
- R5. `cli-smoke`：库用法对齐常见 CLI 场景的教学编排（非替代 `cli_wbtest`）。
- R6. `test-pipeline` smoke-example 覆盖四场景（矩阵或串行全跑）。
- R7. 不引入真网密钥；不改 ci gates/eval/tools（依赖上一子任务路径）。

## Acceptance Criteria

- [ ] AC1. 四场景 `moon run` 均成功（native）。
- [ ] AC2. 旧 `examples/llm_extractor_demo.mbt` + 单包 `moon run examples` 不再作为唯一入口。
- [ ] AC3. smoke job 覆盖四场景。
- [ ] AC4. 示例无 `DEEPSEEK_*` / 真 HTTP。

## Depends

- 建议在 `migrate-ci-role-tree` 完成后开始（避免 CI 文件冲突）；不硬依赖新 ci 路径。

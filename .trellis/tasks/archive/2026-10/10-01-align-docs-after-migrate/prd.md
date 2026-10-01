# 迁移后文档与 spec 对齐

## Goal

在 ci 与 examples 物理迁移完成后，扫尾更新 doc 10 迁移状态、05/architecture/handover/README 残留、`.trellis/spec` 中「current vs target」双轨叙述，消除旧路径作为现行命令的误导。

## Requirements

- R1. doc 10：迁移状态改为已完成（或标注子任务完成日）；现状命令区与目标态合一或删除过时「迁移前」栏。
- R2. `05-test-suite.md`、`architecture.md` 树、`.trellis/spec/library/{directory-structure,quality-guidelines}.md` 使用新路径为现行。
- R3. 主操作文档（README 若有残留、09-handover 常用命令表）更新；历史验证报告（06/07/08）可保留旧路径但加一句「历史路径」或最小替换——优先不破坏史料，在 handover/05/10/spec 上保证现行正确。
- R4. 全库 `rg` 对 `ci/llm_live`、`ci/tuning`、`moon run examples`（无 scene）在**现行入口**文件中应为零（允许 archive/tasks/历史报告例外并列出）。

## Acceptance Criteria

- [x] AC1. doc 10 不再声称「迁移未执行」。
- [x] AC2. spec directory-structure / quality-guidelines 以新路径为权威现行命令。
- [x] AC3. 05 分层表入口命令为新路径；EX smoke 指向四场景。
- [x] AC4. `rg` 报告：workflows/scripts/README/spec 现行区无旧 ci 路径。

## Depends

- `migrate-ci-role-tree` 与 `expand-examples-e2` 均完成后执行。

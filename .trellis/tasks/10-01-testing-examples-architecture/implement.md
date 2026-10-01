# Implement: 测试与示例能力架构（A · 规范）

## Preflight

- [ ] 用户已审阅 `prd.md` + `design.md` 并同意进入实现
- [ ] `implement.jsonl` / `check.jsonl` 已含真实 spec 条目（非仅 `_example`）
- [ ] `python3 ./.trellis/scripts/task.py start`（仅在审阅通过后）

## Checklist（ordered）

1. **写权威页** `docs/project/10-testing-examples-architecture.md`
   - 能力模型表、目标目录树、现状→目标对照、决策树、铁律、E2 四场景说明、建议子任务表
   - 明确「本文为架构权威；用例清单见 05；迁移未执行前命令仍用旧路径」
2. **回链与索引**
   - `docs/project/05-test-suite.md` 文首加指向 10 的短链
   - `docs/project/README.md`（及 `docs/README.md` 若有表项）登记 10
3. **更新 `.trellis/spec/library/directory-structure.md`**
   - packages 表改为目标态角色描述 + 旧路径对照注记
   - 「Where new tests/examples go」决策表（对齐 design 决策树）
4. **更新 `.trellis/spec/library/quality-guidelines.md`**
   - 验证命令：保留现状可跑命令；增补目标态命令并标注「post-migration」
   - 简述 examples vs gates vs tools 边界
5. **（可选轻量）** `docs/project/architecture.md` 中 `ci/` 树若有硬编码旧路径，加「见 10 目标态」注，避免双权威长文重写
6. **自检**
   - 通读 10 与 spec：无互相矛盾路径
   - 确认未改 `.github/workflows/*`、未搬 `ci/` / `examples/` 代码
7. **收尾准备**
   - PRD AC 勾选依据写入 check 记录（由 trellis-check）
   - 子任务建议已在 10 与 prd 一致

## Validation

```bash
# 文档任务：无强制编译门禁；回归确认未误改 CI
git diff --name-only
# 期望仅 docs/ 与 .trellis/spec/（及本 task 产物）
# 可选：确认旧命令仍存在
test -d ci/llm_live && test -d ci/locomo && test -d ci/tuning && test -f examples/llm_extractor_demo.mbt
```

## Risky files / rollback

| 文件 | 风险 | 回滚 |
|------|------|------|
| `10-*.md` 新建 | 低 | 删文件 + 去索引 |
| `05-test-suite.md` | 中（勿删用例表） | 只加文首链，不改分层事实除非与 10 冲突需澄清 |
| `directory-structure.md` / `quality-guidelines.md` | 中（AI 后续依赖） | git checkout |
| workflows / ci 源码 | **本任务禁止改** | — |

## Done when

- AC1–AC6 可在 check 中逐条对照文件证据勾选
- 用户确认可 `finish-work` 或显式拆子任务

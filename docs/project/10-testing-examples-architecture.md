# 测试与示例能力架构

> **本文是「测试 / 门禁 / 评测 / 调参 / 演示」落点的架构权威。**
> 用例清单与 AC 映射见 [05-test-suite](05-test-suite.md)；编码 where-to-put 见 [`.trellis/spec/library/`](../../.trellis/spec/library/)。
>
> **迁移状态**：本页描述目标态（C）。物理目录重排尚未执行——**迁移完成前请继续使用下方「现状命令」**（`ci/llm_live`、`ci/locomo`、`ci/tuning`、`moon run examples`）。

## 1. 能力模型

| 能力 | 层/角色 | 网络/Key | 入口（目标态命令） | CI |
|------|---------|----------|-------------------|-----|
| 纯工程单测/e2e | L0 | 无 | `moon test`（包旁 `*_test.mbt` / `*_wbtest.mbt`） | push 阻塞 |
| Mock LLM 契约/对抗 | L1 | 无（脚本 Provider） | `moon test`（`src/llm_extractor/*_test.mbt`） | push 阻塞 |
| Live LLM 发版门禁 | L2 / **gate** | DeepSeek | `moon run ci/gates/live-llm --target native` | **仅** release |
| 基准评测 | L3 / **eval** | 离线默认；api/live 可选 | `moon run ci/eval/locomo --target native` | 离线 push；live 手工 |
| 调参台 | **tool**（非正式 L） | 无 | `moon run ci/tools/retrieval-tuning --target native` | **不进 CI** |
| 场景示例 | **example** | 无（mock） | `moon run examples/<scene> --target native` | smoke 矩阵（迁移后） |

### 铁律

1. **L0 / L1 永不读取 `DEEPSEEK_*`**（零网络、零密钥）。
2. **L2 永不并入 push CI**（仅 release / tag 门禁）。
3. **examples 永不依赖真网密钥**（只用 mock / 离线默认）。
4. **tools 默认不门禁**（`retrieval-tuning` 不接入 CI，除非未来显式子任务）。
5. **评测语料不塞进包内单测**（L3 语料留在 `ci/eval/locomo/data/`）。

### 现状命令（迁移前 · 现行可跑）

```bash
moon test
moon test --target wasm
moon run ci/llm_live --target native          # L2 gate
moon run ci/locomo --target native            # L3 eval
moon run ci/tuning --target native            # tool（无 CI 调用）
moon run examples --target native             # 现有单包 demo
```

### 目标态命令（post-migration · 路径尚不存在）

```bash
moon test
moon test --target wasm
moon run ci/gates/live-llm --target native
moon run ci/eval/locomo --target native
moon run ci/tools/retrieval-tuning --target native
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
```

## 2. 目标目录树（C · 一步到位）

包旁测试**不外迁**（T1）。`ci/` 按角色子树命名（N2）；`examples/` 为场景子包（E2）。

```
src/                          # 核心；L0 包旁测试不变
src/llm_extractor/            # L1 包旁测试不变
src/cli/                      # CLI + cli_wbtest（L0）
examples/
  basic-store/                # 无 LLM 主路径演示
  llm-extractor/              # mock 提取（现有 demo 迁入）
  conflict-supersede/         # 冲突 / supersede 演示
  cli-smoke/                  # 库用法对齐常见 CLI 场景
ci/
  gates/
    live-llm/                 # ← ci/llm_live
  eval/
    locomo/                   # ← ci/locomo（含 data/）
  tools/
    retrieval-tuning/         # ← ci/tuning
```

## 3. 现状 → 目标态对照

| 现状 | 目标 | 角色 |
|------|------|------|
| `src/**/*_test.mbt`、`*_wbtest.mbt` | 不变 | L0 |
| `src/llm_extractor/*_test.mbt` | 不变 | L1 |
| `ci/llm_live/` | `ci/gates/live-llm/` | L2 gate |
| `ci/locomo/` | `ci/eval/locomo/` | L3 eval |
| `ci/tuning/` | `ci/tools/retrieval-tuning/` | tool（U1，不进 CI） |
| `examples/`（单包 `llm_extractor_demo`） | `examples/{basic-store,llm-extractor,conflict-supersede,cli-smoke}/` | example |

**本任务（A）不执行迁移。** 物理 `git mv`、包 rename、workflow 改路径归子任务（见 §7）。

## 4. 决策树（新能力落哪）

1. 需要**断言回归**且零网络？→ 包旁 `*_test.mbt`（核心 = L0；`llm_extractor` mock = L1）。
2. 需要**真实 LLM** 且阻塞发版？→ `ci/gates/live-llm`（L2）。
3. 需要**基准指标 / 语料评测**？→ `ci/eval/locomo`（L3）。
4. 需要**扫参 / 校准 Config**、不门禁？→ `ci/tools/retrieval-tuning`。
5. 需要**教学/上手可运行演示**（非断言套件）？→ `examples/<scene>`（E2 四场景之一或新增场景子包）。
6. **禁止**：把 live 密钥路径放进 examples；把 tools 默认同等为 L0；把评测语料塞进包内单测。

## 5. E2 四场景与 smoke 意图

| 场景子包 | 意图 | 与断言套件边界 |
|----------|------|----------------|
| `basic-store` | 无 LLM 主路径：open → add → recall → forget | 断言仍在 `store_e2e_test` 等 L0 |
| `llm-extractor` | mock 提取演示（迁入现有 `llm_extractor_demo`） | 契约断言在 L1 `*_test.mbt` |
| `conflict-supersede` | 冲突判定与 supersede 可见编排 | AC-04 断言在 L0/L1 |
| `cli-smoke` | 库用法对齐常见 CLI 场景的教学编排 | 断言以 `cli_wbtest` 为准；示例偏可读演示 |

迁移后期望：**四场景均可 `moon run examples/<scene> --target native`**，并由轻量 smoke 矩阵（非 push 阻塞 L0）覆盖「能跑通」；**不**把示例当作 AC 回归源。

## 6. 文档与 spec 职责

| 产物 | 职责 |
|------|------|
| **本文（10）** | 架构权威：模型、树、决策树、对照表、子任务建议 |
| [05-test-suite](05-test-suite.md) | 用例编目 + AC 映射；文首回链本文；路径字符串可在迁移子任务再改 |
| [`.trellis/spec/library/directory-structure.md`](../../.trellis/spec/library/directory-structure.md) | where-new-code / where-new-tests-examples |
| [`.trellis/spec/library/quality-guidelines.md`](../../.trellis/spec/library/quality-guidelines.md) | 验证命令表（现状 vs 目标态） |
| docs 索引 | 登记本文 |

## 7. 建议子任务（A 验收后用 `--parent` 创建）

| 建议 slug | 边界 |
|-----------|------|
| `migrate-ci-role-tree` | `ci/*` → `gates/live-llm`、`eval/locomo`、`tools/retrieval-tuning` + workflow / README 命令同步 |
| `expand-examples-e2` | 落地四场景子包 + smoke 矩阵；迁入现有 llm demo |
| `align-docs-after-migrate` | 迁移后扫尾：05 路径、handover、architecture.md、spec 命令字符串与旧链接 |

以上子任务**不**在本任务范围内；本页仅作拆分契约。

## 8. Out of scope（本任务 A）

- 目录重排、包路径迁移、`.github/workflows` 改路径
- 新写四场景示例业务代码
- 新增业务 AC 用例集；改 L2/L3 阈值或评测语料
- 把 `retrieval-tuning` 接入 CI

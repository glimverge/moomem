# Design: 测试与示例能力架构（A · 规范）

## Scope of this design

本设计描述 **权威文档与 spec 应编码的目标架构**。物理迁移（C）不在本任务；对照表与子任务边界是给后续执行用的契约。

## Capability model

| 能力 | 层/角色 | 网络/Key | 入口（目标态命令） | CI |
|------|---------|----------|-------------------|-----|
| 纯工程单测/e2e | L0 | 无 | `moon test`（包旁 `*_test.mbt` / `*_wbtest.mbt`） | push 阻塞 |
| Mock LLM 契约/对抗 | L1 | 无（脚本 Provider） | `moon test`（`src/llm_extractor/*_test.mbt`） | push 阻塞 |
| Live LLM 发版门禁 | L2 / **gate** | DeepSeek | `moon run ci/gates/live-llm --target native` | **仅** release |
| 基准评测 | L3 / **eval** | 离线默认；api/live 可选 | `moon run ci/eval/locomo --target native` | 离线 push；live 手工 |
| 调参台 | **tool**（非正式 L） | 无 | `moon run ci/tools/retrieval-tuning --target native` | **不进 CI** |
| 场景示例 | **example** | 无（mock） | `moon run examples/<scene> --target native` | smoke 矩阵（迁移后） |

铁律：L0/L1 不读 `DEEPSEEK_*`；L2 不进 push CI；examples 永不依赖真网密钥；tools 默认不门禁。

## Target directory tree (C · 一步到位)

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

包旁测试**不外迁**（T1）。

## Current → target map

| 现状 | 目标 | 角色 |
|------|------|------|
| `src/**/*_test.mbt`、`*_wbtest.mbt` | 不变 | L0 |
| `src/llm_extractor/*_test.mbt` | 不变 | L1 |
| `ci/llm_live/` | `ci/gates/live-llm/` | L2 gate |
| `ci/locomo/` | `ci/eval/locomo/` | L3 eval |
| `ci/tuning/` | `ci/tools/retrieval-tuning/` | tool |
| `examples/`（单包 demo） | `examples/{basic-store,llm-extractor,conflict-supersede,cli-smoke}/` | example |

## Decision tree（写入 10 与 spec）

1. 需要**断言回归**且零网络？→ 包旁 `*_test.mbt`（核心=L0；llm_extractor mock=L1）。
2. 需要**真实 LLM** 且阻塞发版？→ `ci/gates/live-llm`（L2）。
3. 需要**基准指标 / 语料评测**？→ `ci/eval/locomo`（L3）。
4. 需要**扫参 / 校准 Config**、不门禁？→ `ci/tools/retrieval-tuning`。
5. 需要**教学/上手可运行演示**（非断言套件）？→ `examples/<scene>`（E2 四场景之一或新增场景子包）。
6. 禁止：把 live 密钥路径放进 examples；禁止把 tools 默认同等为 L0；禁止把评测语料塞进包内单测。

## Doc / spec ownership

| 产物 | 职责 |
|------|------|
| `docs/project/10-testing-examples-architecture.md` | 架构权威：模型、树、决策树、对照表、子任务建议 |
| `docs/project/05-test-suite.md` | 用例编目 + AC 映射；文首回链 10；路径描述可在迁移子任务再改 |
| `.trellis/spec/library/directory-structure.md` | where-new-code / where-new-tests-examples |
| `.trellis/spec/library/quality-guidelines.md` | 验证命令表（注明现状命令 vs 目标命令，避免本任务假改 CI） |
| docs 索引 | 登记 10 |

本任务对 quality-guidelines：**以目标态为主叙述，并用一行标明「迁移前仍使用旧路径」**，避免实现期误跑不存在的包。

## Compatibility / rollback

- A 仅 docs/spec → 回滚即还原这些文件。
- C 子任务各自负责 workflow 与 `moon run` 路径原子切换；本设计要求对照表完整以便回滚清单可生成。

## Trade-offs

- 一步到位命名（N2+L2）增大后续迁移 diff，但避免「临时保名」污染终态蓝图。
- E2 四场景增加示例表面积；用「A 只规划、子任务实现」控制本任务范围。
- `cli-smoke` 与 `cli_wbtest` 有重叠风险：蓝图标明示例偏教学编排，断言仍以 wbtest 为准。

## Out of design（child tasks）

- 实际 `git mv` / 包 rename / Actions 改 job
- 编写四场景示例源码与聚合适配
- 将 retrieval-tuning 可选接入 CI（非默认）

# LoCoMo benchmark 基准测试与站点展示

## Goal

把基于 LoCoMo（及项目配套 fixture）的 L3 基准评测，做成**可按发版归档、可在文档站展示**的基准测试能力：每次正式发版后跑 offline + api + live 三档，结果以结构化 JSON 落在仓库并 commit 回 main，在 `site/` 单开一页展示最新成绩、分项指标与相对上一版的 diff。

## Background

仓库已有 L3 评测闭环（`ci/eval/locomo`），本任务是**产品化归档与展示**，不是从零造评测。

| 事实 | 证据 |
|------|------|
| 离线入口 | `moon run ci/eval/locomo --target native` |
| 三档 | hashing（默认）；`--embedder api`；`--live` |
| Push CI | `test-pipeline.yml` → `eval-locomo`（仅离线） |
| 发版 | `release-pipeline.yml`：quality → live-llm → publish/tag |
| 现状缺口 | stdout/`LOCOMO_PASS` 为主；无版本化结果目录；`08-w4-eval-report.md` 仅为一次快照 |
| 语料许可 | `ci/eval/locomo/data/` LoCoMo 切片 CC BY-NC 4.0；不可删署名、不可提交全集 |
| 站点 | Rspress `site/`；`deploy.yml` 在 main push 后部署 Pages |
| 密钥 | 本地 `.env`：`QWEN_*` + `DEEPSEEK_*`；api 档读 `MOOMEM_EMBED_*`（需映射）；live 读 `DEEPSEEK_*` |
| api 档现状 | hybrid vs BM25 −12%，现有硬门禁会 fail（08 报告） |

## Decisions

| ID | Decision |
|----|----------|
| D1 | 发版归档跑 **offline + api + live** |
| D2 | 远程 QWEN embedding + DeepSeek 已配置；本地以 `.env` 为参考 |
| D3 | **分层门禁**：offline 硬门禁（push/quality）；api/live **只归档不阻塞**；站点标 pass/fail |
| D4 | 结果由 **release 后 job 直 commit 回 main**（固定路径 + `chore(benchmark):` 前缀） |
| D5 | 站点页 = **汇总表 + 分项指标 + 相对上一版 diff**（不含逐题明细） |

## Requirements

- R1. 保留 `ci/eval/locomo` 为执行入口；扩展机器可读输出，不另起平行 harness。
- R2. 正式发版成功后（非 dry-run）跑三档，结果写入仓库约定路径并与版本/tag 绑定。
- R3. 结果为 JSON，含各档模型 id、关键指标、gates pass/fail；**禁止写入 API key**。
- R4. `site/` 独立 benchmark 页：最新一次 + 历史版本；分项指标；相对上一版 Δ（D5）。
- R5. 遵守 LoCoMo 派生数据许可红线。
- R6. api：`MOOMEM_EMBED_*`（可由 `QWEN_*` 映射）；live：`DEEPSEEK_*`。
- R7. Push 上 `eval-locomo` 保持零密钥离线门禁；全量三档不进日常 push。
- R8. api/live 未达阈值仍落盘并标红，**不**失败已发布版本、**不**阻断结果 commit（D3）。
- R9. 归档 job commit/push 到 main（D4）；触发现有 Pages 部署即可更新站点。

## Acceptance Criteria

- [x] AC1. 正式发版后流程产出并落盘与版本绑定的三档结果记录。
- [x] AC2. 结果文件可被站点 SSG 读取；文件内无密钥。
- [x] AC3. `site/` 有独立 benchmark 页：最新三档、分项、相对上一版 diff；≥1 条历史时可区分版本。
- [x] AC4. `moon run ci/eval/locomo --target native` 仍可跑通；push `eval-locomo` 不引入密钥依赖。
- [x] AC5. 语料许可与 `data/README.md` 署名未被破坏。
- [x] AC6. Release 环境可解析 embedding（QWEN→`MOOMEM_EMBED_*`）与 DeepSeek；文档说明本地 `.env` 映射。
- [x] AC7. api 档已知未达标时，归档仍写出结果且不升级为发版失败。
- [x] AC8. 归档成功后 main 出现 `chore(benchmark):` 提交；Pages 可展示该版本。

## Out of Scope

- 检索融合算法改进（W5 / P7）。
- 在 LoCoMo 计分子集上调参。
- 重做 `site/` 全站品牌与首页（仅加 benchmark 页与导航入口）。
- 提交 LoCoMo 完整数据集；逐题/逐 case 明细页。
- dry-run 发版跑三档归档（dry-run 跳过归档）。

## Technical Notes

- 建议结果根目录：`benchmarks/locomo/`（schema + `results/<version>.json` + `latest.json` 指针）；站点从该目录或同步副本读取——细节见 `design.md`。
- 归档应在 publish/tag **成功之后**作为独立 job，避免污染 quality 门禁语义。
- Harness 需支持「报告模式」：api/live 收集指标后 exit 0（或 wrapper 吞非零），与 push 离线硬门禁行为分离。

# LoCoMo benchmark 基准测试与站点展示

## Goal

把基于 LoCoMo（及项目配套 fixture）的 L3 基准评测，做成**可按发版归档、可在文档站展示**的基准测试能力：每次正式发版后跑一遍，结果以结构化数据落在仓库内，并在 `site/` 单开一页展示历史与最新成绩。

## Background / Confirmed Facts

仓库已有 L3 评测闭环，本任务是**产品化归档与展示**，不是从零造评测：

| 事实 | 证据 |
|------|------|
| 离线 harness 入口 | `moon run ci/eval/locomo --target native`（`ci/eval/locomo/main.mbt`） |
| 三档能力 | 默认 offline hashing；`--embedder api`；`--live` 提取 |
| Push CI 已跑离线档 | `.github/workflows/test-pipeline.yml` → `eval-locomo` |
| 发版流水线 | `release-pipeline.yml`：quality（含离线 LoCoMo）→ live-llm gate → publish/tag |
| 当前输出形态 | stdout 文本 + `LOCOMO_PASS` / fail；**无版本化 JSON 结果目录** |
| 静态史料报告 | `docs/project/08-w4-eval-report.md`（一次实测快照，非时间序列） |
| 语料与许可 | `ci/eval/locomo/data/`（LoCoMo 切片 CC BY-NC 4.0；不可删署名、不可提交全集） |
| 文档站 | Rspress `site/`（现为脚手架内容）；`deploy.yml` 在 `main` push 后部署 Pages |
| 本地密钥形态 | `.env`（已 gitignore）：`DEEPSEEK_*` + `QWEN_*` |
| Harness 读入变量 | api 档读 `MOOMEM_EMBED_*`（需从 `QWEN_*` 映射）；live 档读 `DEEPSEEK_*` |
| api 档现状 | 实测 hybrid vs BM25 **−12%**，现有硬门禁会 `LOCOMO_FAIL`（见 08 报告）；不宜直接当发版硬阻塞 |

## Decisions

| ID | Decision | Source |
|----|----------|--------|
| D1 | 发版归档档位 = **C：offline + api + live** | 用户 2026-10-01 |
| D2 | 远程已配置支持 embedding 的 QWEN；本地以 `.env` 的 `QWEN_*` / `DEEPSEEK_*` 为参考 | 用户 2026-10-01 |
| D3 | 门禁分层：offline 保持硬门禁（quality/push）；api/live **只归档不阻塞发版**；站点标 pass/fail | 用户 2026-10-01 |
| D4 | 结果写入：**Release job 直接 commit 回 main**（固定路径 + 可识别 commit 前缀） | 用户 2026-10-01 |

## Requirements

- R1. **保留**现有 `ci/eval/locomo` 作为评测执行入口；不另起平行 harness（可扩展结构化输出）。
- R2. 每次**正式发版完成后**，跑 **offline + api + live** 三档，并把该次结果写入仓库内约定路径（与版本号 / tag 关联）。
- R3. 结果数据为机器可读格式（如 JSON），足以驱动站点展示与日后 diff；记录各档模型 id、关键指标、通过/未通过状态。
- R4. 在 `site/` **单独一页**展示基准测试结果（至少：最新一次 + 历史版本列表或趋势）。
- R5. 遵守 LoCoMo 派生数据许可红线：不提交完整数据集；不删 `data/README.md` 署名。
- R6. CI/本地接线：api 档使用 `MOOMEM_EMBED_*`（可由 `QWEN_*` 映射）；live 档使用 `DEEPSEEK_*`；密钥永不写入结果文件或提交进仓。
- R7. Push CI 的离线 `eval-locomo` 门禁语义保持不变（零密钥）；三档全量归档挂在**发版后**路径，不并入日常 push。
- R8. api/live 未达现有硬阈值时仍须落盘完整指标，并在结果与站点上标记未达标；**不得因此失败已发布版本或阻断结果提交**（D3）。
- R9. 发版后归档 job 将结果 **直接 commit/push 到 main**（D4）；路径约定待 design；commit message 使用固定前缀（如 `chore(benchmark):`），且结果 JSON **不含密钥**。

## Acceptance Criteria

- [ ] AC1. 发版后约定流程能产出并落盘至少一条与版本绑定的三档结果记录。
- [ ] AC2. 结果文件在仓库内可被站点构建读取（无需运行时外部服务）；文件内无 API key。
- [ ] AC3. `site/` 有独立 benchmark 页面，能展示最新三档结果；有 ≥1 条历史时能区分版本。
- [ ] AC4. 离线档仍可通过 `moon run ci/eval/locomo --target native` 跑通；push `eval-locomo` 不因本任务引入密钥依赖。
- [ ] AC5. 许可与语料目录约束未被破坏。
- [ ] AC6. Release 环境能解析 embedding（QWEN→`MOOMEM_EMBED_*`）与 DeepSeek 密钥；文档说明本地 `.env` 映射方式。
- [ ] AC7. 在 api 档已知未达标（如 hybrid 低于 bm25 / TARGET_15PCT）场景下，归档 job 仍成功写出结果文件，且不把该失败升级为发版失败。
- [ ] AC8. 归档成功后 main 上出现与版本绑定的结果提交（固定前缀）；随后 Pages 部署可展示该版本（依赖现有 `deploy.yml`）。

## Out of Scope (initial)

- 检索融合算法改进（W5 / P7；见 handover）。
- 在 LoCoMo 计分子集上调参。
- 重做 `site/` 全站品牌与首页（本任务只加 benchmark 页及相关导航入口）。
- 提交 LoCoMo 完整数据集。

## Open Questions

1. ~~发版归档跑哪些档位？~~ → **D1 = C**
2. ~~api/live 门禁策略？~~ → **D3 = 分层（api/live 只归档）**
3. ~~结果如何进入仓库？~~ → **D4 = release job 直 commit main**
4. **站点页展示粒度？** — 阻塞页面信息架构与 JSON schema 字段深度。

## Notes

- 本任务为 **complex**：收敛后需 `design.md` + `implement.md`，再 `task.py start`。
- 可能拆成子任务：`results-archive`（harness 输出 + release 落盘）与 `site-benchmark-page`（展示），父任务管跨交付集成。
- **安全**：`.env` 含真实密钥；规划/实现中只引用变量名，禁止把值写入 PRD/结果 JSON/站点。

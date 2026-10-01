# W4 LoCoMo L3 评测报告（08）

> 定位：PRD §16.1「AI 能力评测」五项指标在本仓库 `ci/locomo` harness 上的**离线实测结果**与达标判定。
> 覆盖范围：离线档（零网络、零密钥）已完成；`--embedder api`（真实嵌入）与 `--live`（提取精度）两档待密钥后补测。
> 复现命令：`moon run ci/locomo --target native`（与 CI `eval-locomo` job 同源）；数据 `ci/locomo/data/`（LoCoMo 派生切片，CC BY-NC 4.0）。
> 评测时间：2026-10-01；harness 交付见 `3786069` 等，CI 接线见 `2d1799f`；本报告数字由产品侧独立复跑确认。

---

## 一、结论速览（对照 PRD §16.1）

| 评测项 | 方法 | Baseline | 目标(v1.0) | 离线实测 | 判定 |
|---|---|---|---|---|---|
| 检索质量 | LoCoMo 子集 Recall@5/MRR@5 | 纯 BM25 单路 | 混合 ≥ 单路 +15% | 混合 **0.335** vs 单路 **0.435**（**−23.0%**） | ⏳ 未达标（见 §二：离线 hashing 无语义，达标判定保留给 `--embedder api` 档） |
| 提取质量 | 100 条金标准 | 全文存入 | Precision ≥ 0.8 | SKIPPED（需 `--live`） | ⏳ 待测 |
| 冲突处理 | 30 组事实变更用例 | 无处理 | supersede 正确率 ≥ 80% | 近重复组 **19/20 = 0.950** | ✅ 达标（语义组离线不计分，见 §四偏差 2） |
| 持久化 | 崩溃注入 + 重启一致性 | — | 100% 通过 | reopen id 集合一致 **1/1** | ✅ 达标（harness 层面；磁盘双槽崩溃恢复另有 L2 用例覆盖） |
| 隔离 | 跨用户检索渗透测试 | — | 0 渗透 | 跨 user 泄漏 **0** | ✅ 达标 |

离线门禁终态：`LOCOMO_PASS`（门禁仅断言：隔离 0、持久化 1/1、supersede ≥0.8；hashing 下 hybrid<bm25 为 report-only）。

---

## 二、检索质量：混合检索 vs BM25 单路（离线 hashing）

**数字**（230 条计分 QA，71 条对抗题已排除；NoConflictJudge 隔离，见 §四偏差 1）：

| 配置 | Recall@5 | MRR@5 |
|---|---:|---:|
| 混合检索（hashing + BM25，RRF k=60，BackfillRecency） | 77/230（**0.335**） | **0.199** |
| BM25 单路（NullEmbedder，BackfillRecency） | 100/230（**0.435**） | **0.310** |
| 混合检索对照（NoBackfill） | 77/230（0.335） | 0.199 |
| abs Δ / rel Δ（Recall@5） | −0.100 / **−23.0%** | — |

分类别（混合检索）：

| category | Recall@5 | MRR@5 |
|---|---:|---:|
| 1 multi-hop | 7/42（0.167） | 0.090 |
| 2 temporal | 32/63（0.508） | 0.325 |
| 3 open-domain | 1/11（0.091） | 0.018 |
| 4 single-hop | 37/114（0.325） | 0.188 |

**如实说明**：

1. 离线档混合检索低于纯 BM25 **23.0%**，与 PRD 目标（+15%）方向相反。根因明确：缺省 `HashingEmbedder` 是词法哈希、无语义能力，其向量与 BM25 的词汇统计高度相关，RRF 融合反而被无语义的向量噪声稀释排序。**这不是混合检索架构的失败，而是缺省嵌入器的已知限制**（README 已知限制第 3 条）。
2. 15% 目标按设计**只在 `--embedder api` 档判定**（`TARGET_15PCT`），离线不伪造达标。该档需一个支持 `/embeddings` 的密钥（注意：DeepSeek **无** embeddings 端点，需 OpenAI / SiliconFlow / DashScope 等其一）。
3. NoBackfill 对照与缺省组数字完全一致（0.335/0.199）：说明本次 230 条查询中补齐（backfill）未贡献额外命中，Recency 兜底条目与 evidence 对话 id 无交集。这是一个值得在 api 档复核的观察点。
4. 评测方法论上，混合检索对 LoCoMo 这类**短轮次、多话题交错**的语料天然处于劣势位（每个 turn 是独立短句，无上下文拼接）；PRD 场景 A/B 的「多轮会话抽取后入库」路径在 `--live` 档才完整成立。离线数字代表「逐轮原文建库」的保守下界。

## 三、其余三项离线结果

- **冲突（近重复 20 组计分）**：supersede 正确 **19/20（0.950）**，超目标 15 个百分点。最小相似度 0.806，距阈值 0.82 仅 **−0.014**（`MARGIN_WARN`，±0.03 带内）——近重复语料在阈值边缘运行，措辞扰动即可能跌破（与调参台 `thr=0.90` 时 supersede 掉到 1/3 的观察一致）。20 组中未通过的 1 组即受此余量影响。
- **语义冲突（10 组）**：仅记录不计分（实测 cos 0.084–0.482，全部低于 0.82 → offline `ignore`），与 README 已知限制第 4 条一致；语义档需 `--llm-judge` / live 判定。
- **持久化**：reopen id 集合一致 1/1。
- **隔离**：双会话建库后交叉检索（各 8 问），跨 user 泄漏 **0**。

## 四、与 PRD/规格的偏差记录

1. **NoConflictJudge 注入**（规格既定）：LoCoMo 含大量近重复轮次，缺省 `SimilarityJudge` 会将旧轮次 supersede 出召回集，污染「只测检索」的指标。检索评测显式注入空判定器，冲突能力改由 §三独立测量。
2. **冲突用例 30 组中 10 组不计分**（规格既定）：语义型变更在缺省离线配置下不可判定（实测 max 相似度 0.482 < 0.67 共存带），计分会把「嵌入器无语义」伪装成「冲突处理失败」；按 W3 验证报告 F4 的实测事实记录为 record-only。
3. **提取精度离线 SKIP**（规格既定）：缺省 `RawExtractor` 将原文整条入库，Precision 天然无意义；打印假数字比不打印更糟。`--live` 档（DeepSeek chat，密钥仅该路径读取）待跑。

## 五、下一步

| 项 | 依赖 | 产出 |
|---|---|---|
| `--embedder api` 检索评测 | 一个 `/embeddings` 密钥 | `TARGET_15PCT` 达标判定 + 本报告 §二补数 |
| `--live` 提取精度 | `DEEPSEEK_API_KEY`（并确认 `DEEPSEEK_MODEL` 非已退役别名） | 100 条金标准 Precision ≥0.8 判定 |
| v0.2.2 发版 | 上述两项的决策（可先行发布离线已验证状态） | tag + mooncakes；L2 门禁需确认 secrets |
| 赛事申报（P0） | — | 10-31 截止，群昵称 = GitHub ID |

## 六、事实勘误（对 W4 执行报告）

执行报告称 `2d1799f`（W4-G）「local, not push」——**不属实**：`git ls-remote origin refs/heads/main` 已指向 `2d1799f`，与本地 HEAD 一致。W4 全部提交均已在远端。

（独立复验明细：native 114/114、wasm/wasm-gc/js 各 101/101、`moon check --target all` 零警告、`TUNING_PASS`、红线 grep 两条为空、CLI `0.2.2`、LoCoMo 全部指标逐字复现——DoD 无一项未通过。）
